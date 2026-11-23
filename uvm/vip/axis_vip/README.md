# AXI4-Stream Verification IP (`axis_vip`)

## 1. VIP Architectural Overview

The `axis_vip` package provides a parameterizable, transaction-level verification component implementing the **ARM AMBA AXI4-Stream Protocol (ARM IHI0051B)**.

In the DMA verification platform, this VIP models high-speed streaming peripherals across two complementary interfaces:
1. **Ingress Stream Master (`axis_wr_agent`):** Connects to the DMA S2MM write datapath (`s_axis_write_data_*`). Acts as an active stream producer, generating structured or random packetized data beats with byte-enable qualifiers (`TKEEP`), sideband attributes (`TID`, `TDEST`, `TUSER`), and packet delimiters (`TLAST`), while reacting to DUT backpressure (`TREADY`).
2. **Egress Stream Slave (`axis_rd_agent`):** Connects to the DMA MM2S read datapath (`m_axis_read_data_*`). Acts as a stream consumer / sink, receiving serialized packets emitted by the DMA read engine and driving receiver flow control backpressure (`TREADY`).

## 2. The Transaction Class (`axis_seq_item`)

The sequence item (`axis_seq_item.sv`) is the fundamental data unit in the streaming testbench. Rather than modeling isolated bus beats, it abstracts complete multi-beat packets as variable-length dynamic arrays, enabling realistic packet-level stimulus and verification.

### 2.1 Randomized Transaction Fields (`rand`)

| Field Name | Type | Width / Range | Protocol Role & Microarchitectural Purpose |
| :--- | :--- | :---: | :--- |
| `data[]` | `rand bit [DATA_WIDTH-1:0]` | Dynamic Array (1 to 256 beats) | Stream payload data words. Each element represents one 32-bit beat in the packet. |
| `keep[]` | `rand bit [KEEP_WIDTH-1:0]` | Dynamic Array `(data.size())` | Byte qualifiers (`TKEEP`), indicating which bytes within a word contain valid data. |
| `id` | `rand bit [ID_WIDTH-1:0]` | Parameterized (Default 8 bits) | Stream source identifier (`TID`). |
| `dest` | `rand bit [DEST_WIDTH-1:0]` | Parameterized (Default 8 bits) | Stream routing destination (`TDEST`). |
| `user[]` | `rand bit [USER_WIDTH-1:0]` | Dynamic Array `(data.size())` | User sideband attribute (`TUSER`) transmitted alongside each beat. |
| `delay[]` | `rand int unsigned` | Dynamic Array `(data.size())` | Inter-beat idle cycle count before asserting `TVALID` (models producer bubbles). |
| `ready_delay` | `rand int unsigned` | Integer ($\ge 0$) | Number of idle cycles the slave deasserts `TREADY` before accepting data. |

### 2.2 Sequence Item Constraints

The transaction class enforces five constraint blocks to ensure legal AMBA AXI4-Stream packet framing:

#### 1. Payload & Dynamic Array Sizing (`c_payload_size`)
Constrains packet lengths to valid ranges and binds all per-beat dynamic arrays to identical lengths:
```systemverilog
constraint c_payload_size {
    data.size() inside {[1:256]};
    keep.size()  == data.size();
    user.size()  == data.size();
    delay.size() == data.size();
}
```

#### 2. Continuous Byte Stream & Sparse TKEEP Rules (`c_keep_default`)
Per ARM AMBA AXI4-Stream Section 2.4.1 (Continuous Byte Stream), payload bytes cannot contain internal holes. All intermediate beats must have full strobes (`4'b1111`), while the terminal beat must start at lane 0 without sparse gaps:
```systemverilog
constraint c_keep_default {
    foreach (keep[i]) {
        if (i < data.size() - 1) {
            keep[i] == {KEEP_WIDTH{1'b1}}; // Full byte lanes for all body beats
        } else {
            // Final beat: contiguous active bytes starting from byte 0
            keep[i] inside {4'b0001, 4'b0011, 4'b0111, 4'b1111};
        }
    }
}
```

#### 3. Inter-Beat Bubble Timing (`c_default_delays`)
Applies soft constraints to randomize producer insertion delays between successive beats (0 to 5 clock cycles):
```systemverilog
constraint c_default_delays {
    foreach (delay[i]) {
        soft delay[i] inside {[0:5]};
    }
}
```

#### 4. Slave Receiver Backpressure Stall Distribution (`c_ready_delay_default`)
Applies soft constraints to randomize receiver wait-state stalls (0 to 5 clock cycles):
```systemverilog
constraint c_ready_delay_default {
    soft ready_delay inside {[0:5]};
}
```

#### 5. Sideband Metadata Tie-Off (`c_sideband_tie_low`)
Defaults sideband signals to zero unless an explicit scenario tests metadata propagation:
```systemverilog
constraint c_sideband_tie_low {
    id   == '0;
    dest == '0;
    foreach (user[i]) {
        user[i] == '0;
    }
}
```

### 2.3 Monitor-Sampled Fields (Non-Randomized)

During passive monitoring, `axis_seq_item` is populated with actual measured bus timing and backpressure metrics:

| Field Name | Type | Width / Range | Monitored Metric |
| :--- | :--- | :---: | :--- |
| `delay[]` | `int unsigned` | Dynamic Array | Measured cycle count of idle bubbles inserted by the producer between beats. |
| `ready_delay` | `int unsigned` | Integer | Cumulative cycle count where `TVALID` was asserted while `TREADY` was held low (measures receiver backpressure duration). |

## 3. Driver Implementation (`axis_wr_driver` & `axis_rd_driver`)

### 3.1 Ingress Stream Write Driver (`axis_wr_driver.sv`)

Operates in **Master / Producer mode**, driving streaming packets into the DMA write engine (`s_axis_write_data_*`).

#### Run Phase Architecture
Initializes all interface signals to an inactive state, synchronizes to reset deassertion, and continuously processes transactions:
```systemverilog
virtual task run_phase(uvm_phase phase);
    reset_signals();
    wait(!vif.rst);
    @(vif.mst_drv_cb);

    forever begin
        seq_item_port.get_next_item(req);
        drive_packet(req);
        seq_item_port.item_done();
    end
endtask : run_phase
```

#### Packet Driving Task (`drive_packet`)
Drives each beat of an AXI-Stream packet sequentially:
1. **Bubble Delay Injection:** If `item.delay[i] > 0`, deasserts `tvalid = 0` and holds data low for the specified number of clock cycles to model transmitter stalls.
2. **Beat Assignment:** Drives `tdata`, `tkeep`, `tid`, `tdest`, and `tuser`.
3. **Terminal Beat Framing:** Asserts `tlast = 1` strictly on the final beat ($i == \text{num\_beats} - 1$).
4. **Valid Assertion & Handshake Synchronization:** Asserts `tvalid = 1`. Awaits clocking block transitions until an accepted handshake occurs (`tvalid && tready` sampled high at a synchronous clock edge):
   ```systemverilog
   vif.mst_drv_cb.tvalid <= 1'b1;
   beat_drive_time = $time;
   @(vif.mst_drv_cb);
   while (!vif.mst_drv_cb.tready || $time == beat_drive_time) begin
       @(vif.mst_drv_cb);
   end
   ```
5. **Bus Cleanup:** Deasserts `tvalid`, `tlast`, `tdata`, and `tkeep` upon packet completion.

### 3.2 Egress Stream Read Driver (`axis_rd_driver.sv`)

Operates in **Slave / Consumer mode**, sinking stream packets from the DMA read engine (`m_axis_read_data_*`).

#### Run Phase & Dual Operating Modes
Branches based on configuration in `axis_agent_config`:
```systemverilog
virtual task run_phase(uvm_phase phase);
    reset_signals();
    wait(!vif.rst);
    @(vif.slv_drv_cb);

    if (cfg.ready_always_high) begin
        run_always_ready();
    end else begin
        run_sequence_driven();
    end
endtask : run_phase
```

#### Mode 1: Ideal Consumer (`run_always_ready`)
Ties `tready = 1` permanently high. The DUT can emit read stream beats on every clock cycle with zero backpressure. The driver continuously monitors reset to deassert `tready` during reset events.

#### Mode 2: Sequence-Directed Backpressure (`run_sequence_driven`)
Allows sequences to apply targeted backpressure stalls:
1. Pulls response item from `seq_item_port`.
2. If `req.ready_delay > 0`, deasserts `tready = 0` for $N$ cycles, forcing the DMA read engine to stall and test its internal skid buffers.
3. Asserts `tready = 1` and waits until an actual handshake occurs (`tvalid && tready`).
4. Deasserts `tready = 0` and calls `seq_item_port.item_done()`.

## 4. Monitor Implementation (`axis_wr_monitor` & `axis_rd_monitor`)

The streaming monitors passively observe physical transactions strictly through clocking block `mon_cb`.

### 4.1 Packet Reconstruction & Sampling Logic (`axis_wr_monitor.sv`)

#### Run Phase Architecture
Monitors physical interface pins continuously, re-synchronizing after any reset event:
```systemverilog
virtual task run_phase(uvm_phase phase);
    forever begin
        wait(!vif.rst);
        @(vif.mon_cb);
        while (!vif.rst) begin
            collect_packet();
        end
    end
endtask : run_phase
```

#### Packet Collection Task (`collect_packet`)
Reconstructs complete multi-beat packets from the raw pin stream:
1. **Backpressure Tracking:** On every clock cycle where `tvalid` is high but `tready` is low, increments `stall_cycles` to quantify how long the consumer stalled the stream.
2. **Beat Capture:** On accepted handshakes (`tvalid && tready`):
   * Records `tdata` into `data_q[$]`.
   * Records `tkeep` into `keep_q[$]`.
   * Records `tuser` into `user_q[$]`.
   * Records inter-beat bubble cycle count into `delay_q[$]`.
3. **Packet Framing Termination:** When `tlast == 1` handshakes, sets `got_last = 1'b1`, terminating the collection loop.
4. **Item Instantiation & Broadcast:**
   * Instantiates a new `axis_seq_item`.
   * Populates `item.data`, `item.keep`, `item.user`, `item.delay`, and stamps `item.ready_delay = stall_cycles`.
   * Broadcasts the assembled packet to `dma_scoreboard` and `dma_coverage` via `ap.write(item)`.
5. **Reset Safety:** If reset asserts before `tlast` occurs, the partial packet is cleanly discarded without corrupting downstream scoreboard queues.

### 4.2 Read Stream Monitor (`axis_rd_monitor.sv`)

The egress monitor connects to `m_axis_read_data_*`, utilizing the exact same clocking-block-synchronized sampling logic. It verifies that:
* The DMA read engine emits well-formed continuous packets.
* `TLAST` is asserted strictly on the final byte of the requested descriptor length.
* Fractional `TKEEP` qualifiers match the expected residual byte count.

## 5. Sequence Library & Traffic Injection (`axis_vip/sequences/`)

The VIP includes a library of specialized sequences located in `sequences/` to generate ingress streaming stimulus and inject controlled slave receiver backpressure.

```
                           +-----------------------------------------------+
                           |          axis_base_seq (Base Class)           |
                           +-----------------------------------------------+
                                                  |
                 +--------------------------------+--------------------------------+
                 |                                                                 |
                 v (Master Producer Mode)                                          v (Slave Consumer Mode)
+------------------------------------+           +---------------------------------+---------------------------------+
|        axis_packet_seq             |           |    axis_rd_backpressure_seq     |        axis_slave_rx_seq        |
+------------------------------------+           +---------------------------------+---------------------------------+
| * Injects structured/randomized    |           | * Drives targeted backpressure  | * Reactive background responder |
|   ingress stream traffic into DUT  |           |   profiles to axis_rd_driver    |   sinking egress stream beats   |
| * Configurable beat bounds         |           | * ZERO_DELAY (wire-speed)       | * Fixed or randomized wait-state|
| * Explicit partial TKEEP patterns  |           | * MIDWAY_FREEZE (20-cycle stall)|   stalls per beat (0-5 cycles)  |
| * Inter-packet & inter-beat delays |           | * FULL_JITTER (random jitter    | * Unbounded background mode or  |
|                                    |           |   with terminal TLAST stall)    |   bounded beat countdown mode   |
+------------------------------------+           +---------------------------------+---------------------------------+
```

### 5.1 Base Sequence (`axis_base_seq.sv`)
Derives from `uvm_sequence #(axis_seq_item)` and establishes parameterized sequence item typedefs and common handles used by all derived streaming sequences.

### 5.2 Ingress Traffic Generation (`axis_packet_seq.sv`)

Used in tests targeting the S2MM write engine to drive ingress packets into `s_axis_write_data_*`.

#### Sequence Configuration Knobs
* `num_packets`: Total number of packets to generate (default: 1).
* `min_beats` & `max_beats`: Constrains the range of beats generated per packet (default: 1 to 16).
* `force_full_last_keep`: When set (`1'b1`), forces `keep` on the final beat to all 1s (`4'b1111`, full 32-bit word).
* `forced_last_keep`: Assigns an explicit byte qualifier pattern to the final beat (e.g., `4'b0001` for 1 byte, `4'b0011` for 2 bytes, `4'b0111` for 3 bytes), testing unaligned write transfers.
* `initial_delay`: Number of idle cycles before the first beat of packet 0.
* `inter_packet_delay`: Idle cycles inserted between consecutive packets ($p > 0$) with `TVALID` held low.
* `inter_beat_delay`: Idle cycles inserted between consecutive beats within a single packet.
* `enable_random_beat_delay`: When `1'b1`, inter-beat delay varies randomly in $[0 : \text{inter\_beat\_delay}]$; when `1'b0`, injects an exact deterministic delay.

#### Execution Implementation (`body()`)
Iterates over $p \in [0, \text{num\_packets}-1]$, creates an `axis_seq_item`, sets initial delay on `delay[0]`, applies inline constraints matching the configured knobs, and executes standard `start_item(pkt)` and `finish_item(pkt)` handshakes:
```systemverilog
virtual task body();
    item_type pkt;
    for (int p = 0; p < num_packets; p++) begin
        pkt = item_type::type_id::create($sformatf("axis_pkt_%0d", p));
        start_item(pkt);
        if (forced_last_keep != '0) begin
            assert(pkt.randomize() with {
                data.size() inside {[min_beats:max_beats]};
                delay[0] == local::cur_pkt_delay;
                foreach (delay[i]) if (i > 0) delay[i] == local::cur_beat_delay;
                keep[data.size() - 1] == local::forced_last_keep;
            });
        end else if (force_full_last_keep) begin
            assert(pkt.randomize() with {
                data.size() inside {[min_beats:max_beats]};
                delay[0] == local::cur_pkt_delay;
                foreach (keep[i]) keep[i] == {KEEP_WIDTH{1'b1}};
            });
        end else begin
            assert(pkt.randomize() with {
                data.size() inside {[min_beats:max_beats]};
                delay[0] == local::cur_pkt_delay;
            });
        end
        finish_item(pkt);
    end
endtask : body
```

### 5.3 Egress Receiver Backpressure Sequences (Slave Consumer Model)

When verifying the MM2S read engine, the read driver (`axis_rd_driver`) operates in slave consumer mode. To stress the DMA read engine's internal FIFOs and skid buffers, two reactive sequences are provided:

#### 1. Targeted Backpressure Profiler (`axis_rd_backpressure_seq.sv`)
Allows tests to inject exact, reproducible backpressure profiles:

```systemverilog
typedef enum {
    AXIS_BP_ZERO_DELAY,     // Wire-speed acceptance (TREADY held high)
    AXIS_BP_MIDWAY_FREEZE,  // Sustained 20-cycle freeze midway (tests FIFO watermarking)
    AXIS_BP_FULL_JITTER     // Random jitter per beat [1:3] + terminal stall on TLAST
} axis_bp_mode_e;
```

* **`AXIS_BP_ZERO_DELAY`:** Drives `req.ready_delay = 0` on every beat, validating maximum throughput and zero-bubble wire-speed streaming.
* **`AXIS_BP_MIDWAY_FREEZE`:** When beat counter matches `freeze_beat` (default: beat 7), asserts `req.ready_delay = freeze_cycles` (default: 20 cycles). This forces the DMA read engine to fill its internal skid FIFO, hit its watermark, and halt upstream AXI memory read requests (`AR` channel).
* **`AXIS_BP_FULL_JITTER`:** Injects randomized wait states (`$urandom_range(min_jitter, max_jitter)`) between intermediate beats, and applies a deliberate `final_stall` (default: 3 cycles) on the terminal beat right before `TLAST`.

#### 2. Background Reactive Responder (`axis_slave_rx_seq.sv`)
Acts as a persistent receiver throughout a test run:
* **Background Operation (`num_beats == 0`):** Runs an infinite loop creating and randomizing `axis_seq_item` responses, sinking egress stream beats continuously with random wait-states ($[0:5]$ cycles) until test termination.
* **Bounded Operation (`num_beats > 0`):** Sinks an exact number of beats before completing, allowing sequences to synchronize phase transitions.
