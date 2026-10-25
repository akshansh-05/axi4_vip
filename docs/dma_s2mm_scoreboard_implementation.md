# AXI4 DMA Subsystem: S2MM Write Engine Scoreboard Implementation Guide

---

## 1. Executive Summary & Verification Objective

The **S2MM (Stream-to-Memory) Write Engine** in the AXI4 DMA Subsystem bridges incoming packetized streaming data from an **AXI4-Stream (AXIS)** slave interface and writes that payload into system memory across an **AXI4 Memory-Mapped (AXI-MM)** write master interface (`AW`, `W`, `B` channels) according to write descriptor instructions.

The **S2MM Scoreboard** in [dma_scoreboard.sv](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/env/dma_scoreboard.sv) acts as the golden reference oracle for the write datapath. It validates five core criteria:
1. **End-to-End Data Integrity**: Zero byte corruption, drops, duplication, or reordering from ingress stream beats to committed memory write beats.
2. **AXI-MM Write Address Progression**: Issues legal, sequentially aligned `AW` bursts matching the requested destination memory address without crossing 4KB page boundaries.
3. **WSTRB Lane Qualification**: Accurate byte strobe generation (`WSTRB`) on first, intermediate, and final beats (including sub-word alignments and early `TLAST` terminations).
4. **Packet-to-Descriptor Association**: Exactly one stream packet per write descriptor, correctly correlating stream bytes with memory writes.
5. **Status Handshake & Cleanliness**: Accurate reporting of written length (`status_len`), matching tag (`status_tag`), error-free completion (`DMA_ERR_NONE`), and zero orphan bytes left in tracking queues.

```
                      +------------------------------------+
                      |     dma_wr_desc_agent (cmd_ap)     |
                      +-----------------+------------------+
                                        | (Write Descriptor Request: Dest Addr, Buffer Len, Tag)
                                        v
                            +-----------------------+
                            |  Stage 1: SCB Queue   |
                            |  s2mm_desc_txn (Tag)  |
                            +-----------+-----------+
                                        |
           +----------------------------+----------------------------+
           |                                                         |
           v                                                         v
+-----------------------+                                 +-----------------------+
|  axis_wr_agent (ap)   |                                 |  axi_wr_agent (ap)    |
+-----------+-----------+                                 +-----------+-----------+
| Stage 2: Ingress Strm |                                 | Stage 3: Memory Write |
| - Golden source data  |                                 | - Verify AW address   |
| - Unpack TKEEP bytes  |                                 | - Unpack WSTRB bytes  |
| - Cap at buffer_len   |                                 | - Check BRESP == OKAY |
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
                      |   dma_wr_desc_agent (status_ap)    |
                      +-----------------+------------------+
                      | Stage 5: Status Retirement         |
                      | - Check in-order tag completion    |
                      | - Verify status_len == transferred |
                      | - Check zero orphan bytes          |
                      | - Retire descriptor from queue     |
                      +------------------------------------+
```

---

## 2. Monitor Sampling Points & Analysis Ports

The scoreboard intercepts transactions published by 4 analysis ports across the VIP agents:

| Analysis Port | Connected Monitor | Driving Channel / Handshake | When Sampled | What Fields Are Captured |
|---|---|---|---|---|
| `imp_dma_wr_cmd` | `dma_wr_desc_monitor` | Descriptor Command FIFO (`valid && ready`) | Rising edge when write descriptor is accepted | `addr`: Destination memory address<br>`len`: Buffer size in bytes<br>`tag`: Descriptor identifier |
| `imp_axis_wr` | `axis_wr_monitor` | AXI4-Stream (`tvalid && tready`) | At packet end upon `TLAST` assertion | `data[]`: Array of stream data words<br>`keep[]`: Byte enables per beat<br>`last`: Stream packet boundary delimiter |
| `imp_axi_wr` | `axi_wr_monitor` | AXI-MM `AW` + `W` + `B` handshakes | Upon `BVALID && BREADY` response | `addr`: AW burst start address<br>`len`: Burst length (`AWLEN`)<br>`data[]`: Array of 32-bit written words<br>`strb[]`: Byte lane enables per beat<br>`bresp`: Write response code |
| `imp_dma_wr_status` | `dma_wr_desc_monitor` | Descriptor Status FIFO (`valid && ready`) | Rising edge when write status is emitted | `status_tag`: Tag of finished descriptor<br>`status_error`: Error code (`DMA_ERR_NONE`)<br>`status_len`: Actual completed byte length |

---

## 3. Core Data Structure: `s2mm_desc_txn`

Each active write descriptor is tracked through a dedicated `s2mm_desc_txn` object:

```systemverilog
class s2mm_desc_txn #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8
);
    bit [ADDR_WIDTH-1:0] dest_addr;                // Destination buffer start address in memory
    bit [LEN_WIDTH-1:0]  buffer_len;               // Maximum allocated buffer size in bytes
    bit [TAG_WIDTH-1:0]  tag;                      // Transaction tracking tag
    byte                 expected_bytes[$];        // Golden payload extracted from ingress stream
    byte                 actual_bytes[$];          // Payload bytes observed in AXI write bursts
    int unsigned         stream_bytes_in;          // Total valid stream bytes received
    int unsigned         bytes_written;            // Total bytes committed to memory
    int unsigned         bytes_matched;            // Running counter of verified matching bytes
    int unsigned         packet_count;             // Stream packets observed (must be 1 per descriptor)
    int unsigned         dropped_bytes;            // Expected dropped bytes if stream > buffer_len
    bit [ADDR_WIDTH-1:0] expected_next_burst_addr; // Next expected AXI write burst address
    bit                  cmd_seen;
    bit                  stream_done;              // Ingress stream TLAST observed
    bit                  status_done;              // Write completion status observed
    dma_error_e          status_error;
    bit [LEN_WIDTH-1:0]  status_len;
endclass : s2mm_desc_txn
```

---

## 4. Five Verification Stages Explained

### Stage 1: Command Registration (`write_dma_wr_cmd`)
When the write descriptor command is accepted by the DUT, the scoreboard:
1. Instantiates `s2mm_desc_txn`.
2. Stores `dest_addr`, `buffer_len`, `tag`.
3. Sets `expected_next_burst_addr = dest_addr & ~(STRB_WIDTH - 1)`.
4. Appends descriptor to `s2mm_queue` and registers it in `s2mm_by_tag[tag]`.

### Stage 2: Ingress Stream Collection (`write_axis_wr`)
In S2MM, the **ingress stream is the golden source**:
1. Unpacks payload bytes using `t.keep[beat][lane]`.
2. **Buffer Overrun Protection**: If `stream_bytes <= buffer_len`, all bytes are pushed to `expected_bytes`. If `stream_bytes > buffer_len`, excess bytes are tracked in `dropped_bytes` (hardware drops excess data in `STATE_DROP_DATA`).
3. Enforces 1-to-1 packet boundary framing per descriptor (`packet_count == 1`).
4. Triggers incremental comparison via `compare_s2mm_data(desc)`.
5. If completion status was already received, calls `check_and_retire_s2mm(desc)`.

### Stage 3: Memory Write Verification (`write_axi_wr`)
When an AXI write burst completes on the bus (`BVALID && BREADY`):
1. **Address Progression**: Verifies `t.addr === desc.expected_next_burst_addr`, then advances `expected_next_burst_addr += ((t.len + 1) * STRB_WIDTH)`.
2. **Byte Strobe Slicing**: For each beat `i` and byte lane `b`, extracts `(t.data[i] >> (8*b)) & 8'hFF` if `t.strb[i][b] == 1` and pushes into `actual_bytes`.
3. **Response Status**: Verifies `t.bresp === 2'b00` (`AXI_RESP_OKAY`).
4. Triggers incremental comparison via `compare_s2mm_data(desc)`.

### Stage 4: Incremental Pair-Wise Comparator (`compare_s2mm_data`)
Pops matching pairs `(exp_b, act_b)` from `expected_bytes` and `actual_bytes` and verifies exact byte equality (`===`). Any deviation increments `s2mm_byte_mismatches` with full byte index and tag context.

### Stage 5: Status Retirement & Cleanliness (`write_dma_wr_status` & `check_and_retire_s2mm`)
Handles the asynchronous race between status emission and bus completion:
1. Verifies in-order status completion tag.
2. Checks `expected_transfer_len = min(buffer_len, stream_bytes_in)`.
3. Verifies `status_len == expected_transfer_len`.
4. Verifies `bytes_matched == expected_transfer_len`.
5. Asserts `expected_bytes.size() == 0` (zero unwritten stream bytes).
6. Asserts `actual_bytes.size() == 0` (zero unverified memory bytes).
7. Verifies `status_error == DMA_ERR_NONE`.
8. Cleans up descriptor from `s2mm_queue` and `s2mm_by_tag`.
