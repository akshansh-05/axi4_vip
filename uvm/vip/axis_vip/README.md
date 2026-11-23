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
