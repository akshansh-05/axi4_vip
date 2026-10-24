# AXI4 DMA Subsystem: MM2S Read Engine Scoreboard Implementation Guide

---

## 1. Executive Summary & Verification Objective

The **MM2S (Memory-to-Stream) Read Engine** in the AXI4 DMA subsystem is responsible for fetching contiguous or aligned blocks of payload data from system memory over an **AXI4 Memory-Mapped (AXI-MM)** read master interface and forwarding that data out over an **AXI4-Stream (AXIS)** master interface as a framed packet terminated by `TLAST`.

The **MM2S Scoreboard** (`dma_scoreboard.sv`) serves as the golden verification oracle. It validates four fundamental correctness criteria:
1. **End-to-End Data Integrity**: Zero payload byte corruption, loss, duplication, or reordering from memory read beats to egress stream beats.
2. **AXI-MM Burst Sequencing & Address Progression**: The DMA engine must issue legal, correctly sequenced AR burst addresses matching the requested descriptor address and burst lengths without cross-boundary violations.
3. **AXIS Packet Framing**: Exactly one AXI-Stream packet with valid byte enables (`TKEEP`) and an asserted `TLAST` on the final beat must be generated per descriptor.
4. **Status Handshake & Cleanliness**: A descriptor status completion must arrive in-order with `DMA_ERR_NONE`, with all expected bytes consumed and zero leftover/orphan bytes.

```
                      +------------------------------------+
                      |     dma_rd_desc_agent (cmd_ap)     |
                      +-----------------+------------------+
                                        | (Descriptor Request: Addr, Len, Tag)
                                        v
                            +-----------------------+
                            |  Stage 1: SCB Queue   |
                            |  mm2s_desc_txn (Tag)  |
                            +-----------+-----------+
                                        |
           +----------------------------+----------------------------+
           |                                                         |
           v                                                         v
+-----------------------+                                 +-----------------------+
|  axi_rd_agent (ap)    |                                 |  axis_rd_agent (ap)   |
+-----------+-----------+                                 +-----------+-----------+
| Stage 2: Mem Read     |                                 | Stage 3: Egress Stream|
| - Verify AR address   |                                 | - Collect TKEEP bytes |
| - Little-endian slice |                                 | - Verify 1-to-1 TLAST |
| - Push expected_bytes |                                 | - Push actual_bytes   |
+-----------+-----------+                                 +-----------+-----------+
           |                                                         |
           +----------------------------+----------------------------+
                                        |
                                        v
                            +-----------------------+
                            | Stage 4: Comparator   |
                            | expected vs actual    |
                            +-----------+-----------+
                                        |
                                        v
                      +-----------------+------------------+
                      |   dma_rd_desc_agent (status_ap)    |
                      +-----------------+------------------+
                      | Stage 5: Status Retirement         |
                      | - Check in-order tag completion    |
                      | - Check verified length == xfer_len|
                      | - Check zero orphan bytes          |
                      | - Delete descriptor from queue     |
                      +------------------------------------+
```

---

## 2. Monitor Sampling Points & Analysis Ports

The scoreboard intercepts transactions published by 4 analysis ports across the VIP agents:

| Analysis Port | Connected Monitor | Driving Channel / Handshake | When Sampled | What Fields Are Captured |
|---|---|---|---|---|
| `imp_dma_rd_cmd` | `dma_rd_desc_monitor` | Descriptor Command FIFO (`valid && ready`) | Rising edge when read descriptor is accepted | `addr`: Source memory address<br>`len`: Total transfer length in bytes<br>`tag`: Descriptor transaction identifier |
| `imp_axi_rd` | `axi_rd_monitor` | AXI-MM AR (`arvalid && arready`) + R (`rvalid && rready`) | At burst end upon `RLAST` assertion | `addr`: AR burst start address<br>`len`: Burst length (`ARLEN`)<br>`data[]`: Complete dynamic array of 32-bit beat data words |
| `imp_axis_rd` | `axis_rd_monitor` | AXI4-Stream (`tvalid && tready`) | At packet end upon `TLAST` assertion | `data[]`: Array of stream beat words<br>`keep[]`: Byte enables per beat<br>`last`: Stream packet boundary delimiter |
| `imp_dma_rd_status` | `dma_rd_desc_monitor` | Descriptor Status FIFO (`valid && ready`) | Rising edge when completion status is emitted | `status_tag`: Tag of finished descriptor<br>`status_error`: Error code (`DMA_ERR_NONE`)<br>`status_len`: Actual completed byte length |

---

## 3. Core Data Structure: `mm2s_desc_txn`

To achieve deterministic tracking across asynchronous, overlapping memory bursts and streaming beats, the scoreboard instantiates a dedicated tracker object `mm2s_desc_txn` for each issued read descriptor:

```systemverilog
class mm2s_desc_txn #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8
);
    bit [ADDR_WIDTH-1:0] start_addr;               // Descriptor source start address
    bit [LEN_WIDTH-1:0]  xfer_len;                 // Total transfer length requested (bytes)
    bit [TAG_WIDTH-1:0]  tag;                      // Tracking tag
    byte                 expected_bytes[$];        // Golden bytes sliced from AXI-MM read bursts
    byte                 actual_bytes[$];          // Egress stream bytes observed on AXIS
    int unsigned         total_bytes_expected;     // Static expected byte count
    int unsigned         bytes_matched;            // Running counter of successfully verified bytes
    int unsigned         packet_count;             // Number of stream packets observed (must be exactly 1)
    int unsigned         stream_pkt_bytes;         // Total bytes in the observed stream packet
    bit [ADDR_WIDTH-1:0] expected_next_burst_addr; // Next expected AXI read burst address
    bit                  cmd_seen;                 // Command registered flag
    bit                  stream_done;              // TLAST observed flag
    bit                  status_done;              // Status observed flag

    function new();
        expected_bytes            = {};
        actual_bytes              = {};
        total_bytes_expected      = 0;
        bytes_matched             = 0;
        packet_count              = 0;
        stream_pkt_bytes          = 0;
        expected_next_burst_addr  = '0;
        cmd_seen                  = 1'b0;
        stream_done               = 1'b0;
        status_done               = 1'b0;
    endfunction
endclass : mm2s_desc_txn
```

### Storage in Scoreboard
```systemverilog
mm2s_txn_type mm2s_queue[$];                   // FIFO queue maintaining in-order pipeline sequence
mm2s_txn_type mm2s_by_tag[bit [TAG_WIDTH-1:0]]; // Associative array for O(1) tag lookup
```

---

## 4. Stage-by-Stage Implementation & Logic Breakdown

### Stage 1: Command Registration (`write_dma_rd_cmd`)

When software writes a read descriptor, `dma_rd_desc_monitor` captures the transfer parameters and publishes a `dma_desc_seq_item` on `cmd_ap`.

```systemverilog
virtual function void write_dma_rd_cmd(dma_desc_item_type t);
    mm2s_txn_type desc;

    desc = new();
    desc.start_addr               = t.addr;
    desc.xfer_len                 = t.len;
    desc.tag                      = t.tag;
    desc.total_bytes_expected     = t.len;
    // Align initial burst expectation to word boundary (STRB_WIDTH = 4 bytes)
    desc.expected_next_burst_addr = t.addr & ~(STRB_WIDTH - 1);
    desc.cmd_seen                 = 1'b1;

    mm2s_queue.push_back(desc);
    mm2s_by_tag[t.tag] = desc;
    mm2s_cmd_count++;

    `uvm_info("SCB_MM2S_CMD", $sformatf("Registered MM2S Read Descriptor: tag=0x%02h, addr=0x%04h, len=%0d bytes",
              t.tag, t.addr, t.len), UVM_MEDIUM)
endfunction : write_dma_rd_cmd
```

#### Key Verification Operations:
- Allocates a fresh tracker `desc`.
- Sets `expected_next_burst_addr` to the word-aligned start address (`t.addr & ~(STRB_WIDTH - 1)`).
- Pushes `desc` into `mm2s_queue` to track pipeline order.
- Indexes `desc` in `mm2s_by_tag[t.tag]` for rapid retirement lookups.

---

### Stage 2: Memory Read Slicing & Burst Address Progression (`write_axi_rd`)

The DMA read master issues AXI4 read requests to fetch memory data. When the burst completes (`RLAST`), `axi_rd_monitor` publishes the complete `axi_seq_item` to `imp_axi_rd`.

```systemverilog
virtual function void write_axi_rd(axi_item_type t);
    mm2s_txn_type desc;

    if (mm2s_queue.size() == 0) begin
        `uvm_error("SCB_MM2S_UNEXP_RD", $sformatf("Observed AXI Read burst (addr=0x%04h) without active MM2S descriptor!", t.addr))
        return;
    end

    desc = mm2s_queue[0];

    // 1. Verify AXI Read burst address progression
    if (t.addr !== desc.expected_next_burst_addr) begin
        `uvm_error("SCB_MM2S_BURST_ADDR", $sformatf("MM2S AXI Read burst address mismatch for tag 0x%02h! Expected=0x%04h, Actual=0x%04h",
                   desc.tag, desc.expected_next_burst_addr, t.addr))
        mm2s_addr_errors++;
    end
    desc.expected_next_burst_addr += ((t.len + 1) * STRB_WIDTH);

    // 2. Unpack 32-bit read data words into individual byte stream (Windowing)
    for (int i = 0; i <= t.len; i++) begin
        for (int b = 0; b < STRB_WIDTH; b++) begin
            int byte_addr = (t.addr & ~(STRB_WIDTH - 1)) + (i * STRB_WIDTH) + b;
            // Only collect bytes within descriptor boundary [start_addr, start_addr + xfer_len - 1]
            if (byte_addr >= desc.start_addr && byte_addr < (desc.start_addr + desc.xfer_len)) begin
                byte byte_val = (t.data[i] >> (8 * b)) & 8'hFF;
                desc.expected_bytes.push_back(byte_val);
            end
        end
    end

    compare_mm2s_data(desc);
endfunction : write_axi_rd
```

#### Key Verification Operations:
1. **Burst Address Progression**:
   - Compares `t.addr` directly against `desc.expected_next_burst_addr`.
   - Increments `expected_next_burst_addr` by `(t.len + 1) * STRB_WIDTH` to verify that multi-burst transfers progress monotonically without gaps or address jumps.
2. **Unaligned Byte Windowing**:
   - System memory read words are 32-bit (`STRB_WIDTH = 4`). If a transfer begins at unaligned address `0x1001` or ends unaligned, the AXI burst still fetches full 32-bit aligned words.
   - The double-loop slices each 32-bit word into little-endian bytes (`b = 0, 1, 2, 3`) and calculates `byte_addr`.
   - **Boundary Filter**: Only bytes within `[start_addr, start_addr + xfer_len - 1]` are pushed into `desc.expected_bytes[$]`. Unwanted prefix/suffix pad bytes are discarded.
3. **Trigger Comparator**: Immediately calls `compare_mm2s_data(desc)`.

---

### Stage 3: Egress Stream Collection & Packet Framing (`write_axis_rd`)

The DMA read engine forwards the fetched bytes over the AXI4-Stream interface. When a packet ends (`TLAST`), `axis_rd_monitor` publishes an `axis_seq_item` to `imp_axis_rd`.

```systemverilog
virtual function void write_axis_rd(axis_item_type t);
    mm2s_txn_type desc;
    int unsigned pkt_bytes = 0;

    if (mm2s_queue.size() == 0) begin
        `uvm_error("SCB_MM2S_UNEXP_STREAM", "Observed egress stream packet on AXIS without active MM2S descriptor!")
        return;
    end

    desc = mm2s_queue[0];

    // 1. Count packet payload bytes across all beats using TKEEP
    for (int beat = 0; beat < t.data.size(); beat++) begin
        for (int lane = 0; lane < STRB_WIDTH; lane++) begin
            if (t.keep[beat][lane]) begin
                byte act_byte = (t.data[beat] >> (8 * lane)) & 8'hFF;
                desc.actual_bytes.push_back(act_byte);
                pkt_bytes++;
            end
        end
    end

    // 2. Check 1-to-1 packet boundary framing per descriptor
    if (desc.packet_count > 0) begin
        `uvm_error("SCB_MM2S_EXTRA_PKT", $sformatf("MM2S descriptor tag 0x%02h produced multiple stream packets! (packet #%0d)",
                   desc.tag, desc.packet_count + 1))
        mm2s_pkt_errors++;
    end

    // 3. Verify packet length at TLAST matches descriptor requested length
    if (pkt_bytes != desc.xfer_len) begin
        `uvm_error("SCB_MM2S_PKT_LEN", $sformatf("MM2S Stream packet terminated with TLAST at %0d bytes, but descriptor requested %0d bytes! (tag 0x%02h)",
                   pkt_bytes, desc.xfer_len, desc.tag))
        mm2s_pkt_errors++;
    end

    desc.packet_count++;
    desc.stream_pkt_bytes = pkt_bytes;
    desc.packet_count++;
    desc.stream_pkt_bytes = pkt_bytes;
    desc.stream_done      = 1'b1;

    compare_mm2s_data(desc);

    // If status was already received, both streams are complete -> retire descriptor
    if (desc.status_done) begin
        check_and_retire_mm2s(desc);
    end
endfunction : write_axis_rd
```

#### Key Verification Operations:
1. **TKEEP Byte Extraction**:
   - Inspects `t.keep[beat][lane]`. Only valid byte lanes are extracted and pushed into `desc.actual_bytes[$]`.
2. **1-to-1 Packet Framing Check**:
   - By architectural design, each MM2S descriptor MUST produce exactly **one** discrete AXI-Stream packet terminated by `TLAST`. If `desc.packet_count > 0`, an illegal fragmentation error is flagged.
3. **Packet Length Verification**:
   - Asserts that the total number of bytes in the stream packet (`pkt_bytes`) matches `desc.xfer_len` at `TLAST`.
4. **Trigger Comparator**: Calls `compare_mm2s_data(desc)`.
5. **Retirement Check**: If `desc.status_done` has already arrived, triggers `check_and_retire_mm2s(desc)`.

---

### Stage 4: Incremental Pair-Wise Comparator (`compare_mm2s_data`)

The comparison function is completely decoupled and incremental. It executes in a lockstep `while` loop whenever either the AXI read channel or the AXIS stream channel delivers new bytes:

```systemverilog
virtual function void compare_mm2s_data(mm2s_txn_type desc);
    while (desc.expected_bytes.size() > 0 && desc.actual_bytes.size() > 0) begin
        byte exp_b = desc.expected_bytes.pop_front();
        byte act_b = desc.actual_bytes.pop_front();
        mm2s_bytes_checked++;

        if (exp_b === act_b) begin
            mm2s_byte_matches++;
            desc.bytes_matched++;
        end else begin
            mm2s_byte_mismatches++;
            `uvm_error("SCB_MM2S_DATA_MISMATCH", $sformatf("MM2S Data Mismatch at byte %0d for tag 0x%02h: Expected=0x%02h, Actual=0x%02h",
                       desc.bytes_matched, desc.tag, exp_b, act_b))
        end
    end
endfunction : compare_mm2s_data
```

#### Advantages:
- **Asynchronous Decoupling**: If AXI read bursts arrive faster than AXIS stream sinks (or vice versa), uncompared bytes safely buffer in the queues until the partner arrives.
- **Immediate Failure Pinpointing**: The moment a corrupted byte emerges on the stream, an error is reported with the exact byte offset (`bytes_matched`), descriptor tag, expected hex value, and actual hex value.

---

### Stage 5: Status Retirement & Two-Way Cleanliness Synchronization (`write_dma_rd_status` & `check_and_retire_mm2s`)

In the DMA hardware architecture, the status channel and the stream output FIFO are physically separate pipelines:
- The internal core writes the final beat into the output FIFO and sets `read_desc_status_valid` concurrently.
- Depending on output FIFO latency and downstream `TREADY` handshaking, the status pulse can arrive **before, concurrently with, or after** the stream packet's final `TLAST` beat completes.
- To prevent false races, the scoreboard requires **both** `desc.status_done` and `desc.stream_done` to be set before calling `check_and_retire_mm2s()`:

```systemverilog
virtual function void write_dma_rd_status(dma_desc_item_type t);
    mm2s_txn_type desc;
    mm2s_status_count++;

    if (!mm2s_by_tag.exists(t.status_tag)) begin
        `uvm_error("SCB_MM2S_UNEXP_TAG", $sformatf("MM2S Status returned unknown tag: 0x%02h", t.status_tag))
        mm2s_status_mismatches++;
        return;
    end

    desc = mm2s_by_tag[t.status_tag];
    desc.status_done  = 1'b1;
    desc.status_error = t.status_error;

    // Check in-order completion assertion for the single-pipeline MM2S engine
    if (mm2s_queue.size() > 0 && mm2s_queue[0].tag !== t.status_tag) begin
        `uvm_error("SCB_MM2S_OOO", $sformatf("MM2S completion status tag 0x%02h arrived out-of-order! Expected queue head tag 0x%02h",
                   t.status_tag, mm2s_queue[0].tag))
        mm2s_status_mismatches++;
    end

    // If egress stream packet has already completed, retire descriptor now.
    // If stream packet is still draining through output FIFO, write_axis_rd will retire it.
    if (desc.stream_done) begin
        check_and_retire_mm2s(desc);
    end
endfunction : write_dma_rd_status

virtual function void check_and_retire_mm2s(mm2s_txn_type desc);
    int found_idx = -1;

    // 1. Drain any remaining comparisons
    compare_mm2s_data(desc);

    // 2. Check 1-to-1 packet boundary framing per descriptor
    if (desc.packet_count != 1) begin
        `uvm_error("SCB_MM2S_PKT_COUNT", $sformatf("MM2S descriptor tag 0x%02h expected 1 stream packet, but saw %0d!",
                   desc.tag, desc.packet_count))
        mm2s_pkt_errors++;
    end

    // 3. Verify total byte count matched descriptor transfer length
    if (desc.bytes_matched != desc.xfer_len) begin
        `uvm_error("SCB_MM2S_LEN_MISMATCH", $sformatf("MM2S Length mismatch for tag 0x%02h: Expected=%0d bytes, Verified=%0d bytes",
                   desc.tag, desc.xfer_len, desc.bytes_matched))
        mm2s_status_mismatches++;
    end

    // 4. Verify no leftover unmatched bytes
    if (desc.expected_bytes.size() != 0) begin
        `uvm_error("SCB_MM2S_ORPHAN_EXP", $sformatf("MM2S Tag 0x%02h completed with %0d unconsumed expected bytes!",
                   desc.tag, desc.expected_bytes.size()))
        mm2s_status_mismatches++;
    end
    if (desc.actual_bytes.size() != 0) begin
        `uvm_error("SCB_MM2S_ORPHAN_ACT", $sformatf("MM2S Tag 0x%02h completed with %0d uncompared actual stream bytes!",
                   desc.tag, desc.actual_bytes.size()))
        mm2s_status_mismatches++;
    end

    // 5. Verify completion status error code
    if (desc.status_error != DMA_ERR_NONE) begin
        `uvm_error("SCB_MM2S_ERR", $sformatf("MM2S Descriptor tag 0x%02h completed with error code: %s (0x%0x)",
                   desc.tag, desc.status_error.name(), desc.status_error))
        mm2s_status_mismatches++;
    end

    // 6. Clean up completed descriptor by tag across both lookup structures
    foreach (mm2s_queue[i]) begin
        if (mm2s_queue[i].tag == desc.tag) begin
            found_idx = i;
            break;
        end
    end
    if (found_idx >= 0) begin
        mm2s_queue.delete(found_idx);
    end
    mm2s_by_tag.delete(desc.tag);

    `uvm_info("SCB_MM2S_PASS", $sformatf("MM2S Transfer Complete & Verified: tag=0x%02h, len=%0d bytes",
              desc.tag, desc.bytes_matched), UVM_LOW)
endfunction : check_and_retire_mm2s
```

#### Final Cleanliness Checks:
- `check_phase`: Verifies that `mm2s_queue.size() == 0` at end of test. If any descriptors were submitted but never completed, `SCB_MM2S_HANG` is flagged.
- `report_phase`: Summarizes total commands, completions, verified bytes, and reports `[TEST PASSED]` or `[TEST FAILED]`.

---

## 5. Architectural Deep-Dive: MM2S vs S2MM Boundary Terminations

A key design and verification principle centers on why early burst termination behaves differently between MM2S and S2MM:

### MM2S Read Engine (Memory -> Stream)
- **AXI4 Specification Rule (ARM IHI 0022H, Section A3.4.4)**:
  > *"A slave must not terminate a read burst early."*
- When the DMA read engine issues an AR burst with `ARLEN = N`, the memory slave **must** return exactly `N + 1` data beats.
- An early `RLAST` assertion by a slave is a catastrophic protocol violation. The VIP `axi_rd_monitor.sv` detects and flags this protocol violation (`[RESPONDER] Premature RLAST`).
- The DMA hardware read engine state machine counts beats against `ARLEN`. If a slave attempts early termination, the hardware ignores premature `RLAST` and waits for all beats. Hence, the MM2S scoreboard does not expect or support early RLAST.

### S2MM Write Engine (Stream -> Memory)
- **AXI4-Stream Specification Rule (ARM IHI 0051B)**:
  > In AXI-Stream, packets are variable length. The sender can assert `TLAST` at any time.
- If software configures an S2MM descriptor for 64 bytes, but the stream source asserts `TLAST` after only 32 bytes, this is **completely legal**.
- The DMA write engine transitions to `STATE_FINISH_BURST`, issuing dummy beats with `WSTRB = 4'b0000` to satisfy the active AXI write burst without modifying memory, and records `status_len = 32`.
- When we build the S2MM scoreboard, it will explicitly handle and verify variable-length packet terminations.

---

## 6. Standalone Sanity Test Plan for MM2S

To verify the MM2S scoreboard in isolation before introducing S2MM:

1. In `dma_sanity_test.sv`:
   - Phase 2 (S2MM write sequence and ingress stream driving) is **commented out**.
   - Phase 1 (MM2S read transfer of 64 bytes at address `0x1000`, tag `0x01`) executes standalone.
2. Expected Execution Flow:
   ```
   Time 0: Test starts, resets DUT and VIPs.
   Time ~100ns: Phase 1 starts. Read descriptor submitted: addr=0x1000, len=64, tag=0x01.
   Stage 1: SCB registers MM2S descriptor.
   Time ~150ns: DMA issues AXI read burst (addr=0x1000, len=15).
   Stage 2: SCB captures 16 beats (64 bytes), unpacks and queues in expected_bytes.
   Time ~180ns: DMA drives egress AXI-Stream beats to axis_rd_agent.
   Stage 3: SCB captures stream beats, verifies TKEEP, sees TLAST on beat 16.
   Stage 4: Comparator verifies all 64 bytes match 1-to-1.
   Time ~220ns: DMA asserts descriptor status completion (tag=0x01, error=0).
   Stage 5: SCB confirms in-order completion, verified byte count == 64, retires descriptor.
   SCB report_phase prints:
   ------------------ MM2S SCOREBOARD SUMMARY ------------------
   Commands: 1 | Status Done: 1 | Hung: 0
   Bytes Checked: 64 | Matches: 64 | Mismatches: 0
   Packet Errors: 0 | Addr Errors: 0 | Status Errors: 0
   VERDICT: [PASSED] MM2S transfer verified successfully.
   -------------------------------------------------------------

---

## 7. Next Steps

Once the MM2S read transfer and scoreboard execution is confirmed in simulation:
1. Re-enable Phase 2 in `dma_sanity_test.sv`.
2. Implement the **S2MM (Stream-to-Memory) Scoreboard** following the exact same 5-stage architectural pattern with support for early `TLAST` and byte-enable tracking.
