# Verification Plan (vPlan): AXI4 DMA Subsystem (Standalone Mode)

**Author:** Akshansh Chaurasia  
**Supervisor:** Dr. Rakesh Palisetty  
**Institution:** Shiv Nadar University, Greater Noida  
**Department:** Department of Electrical Engineering  
**Project:** Minor Project — Design & UVM Verification of AXI4 DMA Subsystem  
**Target RTL:** `axi_dma.v`, `axi_dma_rd.v`, `axi_dma_wr.v`  
**Testbench:** SystemVerilog UVM 1.2 Verification Environment (`axi4_vip`)  
**Sign-off Target:** 100% Functional Coverage (FC) across all 13 Covergroups & >95% Code Coverage (CC)  

---

## 1. Executive Summary & Verification Strategy

The objective of this verification plan is to achieve **100% Functional Coverage** and **maximum Code Coverage** (Line, Branch, FSM, Condition, Toggle) for the AXI4 Direct Memory Access (DMA) core operating in **DMA Standalone Mode**.

In this configuration:
- The **DMA DUT** acts as an **AXI4 Memory-Mapped Master** to external memory (generating `AR`, `R`, `AW`, `W`, `B` transactions).
- The testbench coordinates **Active AXI-MM Slave Responders**, **AXI-Stream VIPs**, and **Descriptor Agents** to stimulate the DMA across all operating points, boundary conditions, and hardware recovery states.

```
                                UVM DMA Verification Topology
  +---------------------------------------------------------------------------------------+
  |                                                                                       |
  |   +-----------------------+     +-----------------------+     +-------------------+   |
  |   | Read Descriptor Agent |     | Write Descriptor Agent|     | Stream Write VIP  |   |
  |   | (s_axis_read_desc_*)  |     | (s_axis_write_desc_*) |     | (s_axis_wr_data_*)|   |
  |   +-----------+-----------+     +-----------+-----------+     +---------+---------+   |
  |               |                             |                           |             |
  |               +----------------------+      |      +--------------------+             |
  |                                      |      |      |                                  |
  |                                      v      v      v                                  |
  |                               +-----------------------------+                         |
  |                               |    AXI4 DMA DUT (DUT Core)  |                         |
  |                               |  (axi_dma_rd / axi_dma_wr)  |                         |
  |                               +--------------+--------------+                         |
  |                                              |                                        |
  |                        +---------------------+---------------------+                  |
  |                        |                                           |                  |
  |                        v                                           v                  |
  |             +---------------------+                     +---------------------+       |
  |             |  Stream Read VIP    |                     | AXI-MM Slave VIP    |       |
  |             | (m_axis_rd_data_*)  |                     | (AR, R, AW, W, B)   |       |
  |             +---------------------+                     +---------------------+       |
  |                                                                                       |
  |               All 8 Interface Monitors feed into dma_coverage (13 Covergroups)        |
  +---------------------------------------------------------------------------------------+
```

---

## 2. RTL Micro-Architecture & Code Coverage Targets

To achieve high **Code Coverage (CC)**, the stimulus in our vPlan is mapped directly against the physical hardware structures inside the RTL:

### 2.1 Statement & Line Coverage
Every reachable operational statement in `axi_dma_rd.v` and `axi_dma_wr.v` must execute at least once.

### 2.2 Branch & Decision Coverage
All `if-else` and `case` branches in the RTL must be toggled across both `true` and `false` evaluations:
- **Burst Slicing Decisions:** `op_word_count_reg <= AXI_MAX_BURST_SIZE` (True: single burst, False: multi-burst).
- **4KB Page Boundary Detection:** `((addr_reg & 12'hfff) + burst_size) >> 12 != 0` (True: 4KB crossed, False: normal burst).
- **Alignment Branches:** `ENABLE_UNALIGNED` branch (`offset > 0` vs `zero_offset`).
- **Early Stream Termination:** Stream asserts `TLAST` while `output_cycle_count > 0`.
- **Excess Stream Data:** Descriptor bytes satisfied while stream still has active beats without `TLAST`.

### 2.3 FSM State & Transition Coverage
Every FSM state and every legal transition between states must be exercised:

| FSM Name | Module | States | Required State Transitions |
| :--- | :--- | :--- | :--- |
| **`axi_state`** (AR Generator) | `axi_dma_rd.v` | `IDLE`, `START` | `IDLE -> START`, `START -> START` (multi-burst), `START -> IDLE` |
| **`axis_state`** (R Assembler) | `axi_dma_rd.v` | `IDLE`, `READ` | `IDLE -> READ`, `READ -> READ` (multi-beat), `READ -> IDLE` |
| **`state`** (Write Controller) | `axi_dma_wr.v` | `IDLE`, `START`, `WRITE`, `FINISH_BURST`, `DROP_DATA` | `IDLE -> START`, `START -> WRITE`, `WRITE -> START` (multi-burst), `WRITE -> IDLE`, `WRITE -> FINISH_BURST` (early TLAST), `WRITE -> DROP_DATA` (excess data), `FINISH_BURST -> IDLE`, `DROP_DATA -> IDLE` |

### 2.4 Expression / Condition Coverage
All multi-input boolean conditions must be tested with combinations that verify each term independently controls the outcome:
- `s_axis_read_desc_ready_next = !axis_cmd_valid_reg && enable;`
- `s_axis_write_desc_ready_next = enable && active_count_av_reg;`
- `out_fifo_half_full_reg <= (wr_ptr - rd_ptr) >= 16;`

### 2.5 Toggle Coverage
Every bit of all interface ports and key internal registers must toggle `0 -> 1` and `1 -> 0`:
- Address buses (`addr[15:0]`)
- Length counters (`len[19:0]`)
- Byte strobes (`wstrb[3:0]`, `tkeep[3:0]`)
- Error codes (`error[3:0]`)

---

## 3. Functional Coverage Model Architecture (13 Covergroups)

The functional coverage model is implemented in `uvm/env/dma_coverage.sv` as a hierarchical 5-tier architecture:

```
                           13-Covergroup Model Architecture
  ┌──────────────────────────────────────────────────────────────────────────────────┐
  │ Tier 1: Descriptor Interfaces                                                    │
  │   - cg_dma_rd_desc        : Read descriptor length, tag, aligned/unaligned addr   │
  │   - cg_dma_rd_desc_status : Read completion status valid pulse, tag, error codes │
  │   - cg_dma_wr_desc        : Write descriptor length, tag, aligned/unaligned addr  │
  │   - cg_dma_wr_desc_status : Write completion status length, tag, error codes     │
  ├──────────────────────────────────────────────────────────────────────────────────┤
  │ Tier 2: AXI-Stream Data Interfaces                                               │
  │   - cg_axis_rd_stream     : Egress stream beats (1, 2-15, 16, >16), TKEEP masks  │
  │   - cg_axis_wr_stream     : Ingress stream beats, TKEEP masks, inter-beat delays  │
  ├──────────────────────────────────────────────────────────────────────────────────┤
  │ Tier 3: AXI4 Master Memory-Mapped Interfaces                                     │
  │   - cg_dma_axi_ar_master  : ARADDR alignment, ARLEN (1, 2-15, 16), 4KB crossings  │
  │   - cg_dma_axi_r_master   : RDATA beats, RRESP (OKAY, SLVERR, DECERR), RLAST     │
  │   - cg_dma_axi_aw_master  : AWADDR alignment, AWLEN (1, 2-15, 16), 4KB crossings  │
  │   - cg_dma_axi_w_master   : WDATA beats, WSTRB lane masks, WLAST generation      │
  │   - cg_dma_axi_b_master   : BRESP (OKAY, SLVERR, DECERR) retirement             │
  ├──────────────────────────────────────────────────────────────────────────────────┤
  │ Tier 4: Cross-Tier Protocol & Slicing Matrix                                     │
  │   - cg_cross_tier         : Cross descriptor len x AXI burst count (slicing)     │
  │                           : Cross 4KB crossing x burst length                    │
  │                           : Cross unaligned address x TKEEP / WSTRB masks        │
  ├──────────────────────────────────────────────────────────────────────────────────┤
  │ Tier 5: Hardware Recovery & Corner Cases                                         │
  │   - cg_write_abort        : STATE_FINISH_BURST (early TLAST with WSTRB=0)        │
  │                           : STATE_DROP_DATA (excess stream data drain)           │
  └──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Feature Decomposition & Verification Scenarios

### Feature 1: MM2S Memory-to-Stream Read Transfers

#### Objective
Verify that the DMA correctly reads data from AXI memory, packages it into AXI-Stream beats, and delivers it to downstream destinations.

#### Test Scenarios:
1. **Sanity Single-Burst Read (1 to 16 beats):**
   - Transfer length: 4 to 64 bytes (`ARLEN = 0` to `15`).
   - Verifies 1-to-1 mapping between memory read beats and stream output beats.
   - Bins hit: `cg_dma_rd_desc.cp_len.single_beat`, `cg_dma_axi_ar_master.cp_arlen.burst_16`.
2. **Multi-Burst Segmentation & Slicing (>16 beats):**
   - Transfer length: 128 bytes, 256 bytes, 1024 bytes.
   - Verifies that the AR generator slices the transfer into multiple consecutive 16-beat bursts (`ARLEN = 15`) and updates `addr_reg` incrementally.
   - Bins hit: `cg_cross_tier.cross_rd_slicing_len`, `cg_dma_rd_desc.cp_len.large_burst`.
3. **4KB Address Boundary Crossing:**
   - Program descriptor with `start_addr = 0x0FE0` and `length = 64 bytes` (spans across `0x1000`).
   - Verifies that the AR generator detects the boundary, clamps Burst 1 to end at `0x0FFF` (8 beats), and issues Burst 2 starting at `0x1000` (8 beats).
   - Bins hit: `cg_dma_axi_ar_master.cp_4k_cross.cross_4k`, `cg_cross_tier.cross_rd_4k_boundary`.
4. **Unaligned Byte Start Addressing:**
   - Program `start_addr` with offsets `+1`, `+2`, `+3` (e.g. `0x1001`, `0x1002`, `0x1003`).
   - Verifies that the barrel shifter correctly aligns requested bytes to byte lane 0 of the stream output.
   - Bins hit: `cg_dma_rd_desc.cp_addr_offset`, `cg_dma_axi_ar_master.cp_araddr_align`.
5. **Partial Final Beat (TKEEP mask):**
   - Program transfer length not a multiple of 4 bytes (e.g. 61 bytes, 62 bytes, 63 bytes).
   - Verifies that the final stream beat asserts `TKEEP = 4'b0001`, `4'b0011`, or `4'b0111` along with `TLAST = 1`.
   - Bins hit: `cg_axis_rd_stream.cp_tkeep_last`.
6. **Stream Receiver Backpressure:**
   - Deassert `m_axis_read_data_tready` while read data is streaming.
   - Verifies that the 32-entry output skid FIFO absorbs in-flight beats and deasserts `m_axi_rready` when half-full.
   - Bins hit: `cg_axis_rd_stream.cp_inter_beat_delay`.

---

### Feature 2: S2MM Stream-to-Memory Write Transfers

#### Objective
Verify that incoming stream packets are packaged into legal AXI write bursts and written to memory without data loss or corruption.

#### Test Scenarios:
1. **Sanity Single-Burst Write (1 to 16 beats):**
   - Descriptor buffer capacity: 64 bytes. Ingress stream packet: 16 beats.
   - Verifies concurrent acceptance, generation of `AWLEN = 15`, streaming on W channel, and retirement on B channel.
   - Bins hit: `cg_dma_wr_desc.cp_len.single_beat`, `cg_dma_axi_aw_master.cp_awlen.burst_16`.
2. **Multi-Burst Write Segmentation (>16 beats):**
   - Buffer length: 128 bytes, 256 bytes, 512 bytes. Stream packet matches length.
   - Verifies multiple AW requests with `status_fifo` tracking each burst and pulsing completion status only on the final burst.
   - Bins hit: `cg_cross_tier.cross_wr_slicing_len`, `cg_dma_wr_desc.cp_len.large_burst`.
3. **4KB Address Boundary Crossing on Write:**
   - Destination address: `0x1FE0`, transfer length: 64 bytes.
   - Verifies AW generator splits the burst at `0x2000`, preventing AXI protocol violations.
   - Bins hit: `cg_dma_axi_aw_master.cp_4k_cross.cross_4k`, `cg_cross_tier.cross_wr_4k_boundary`.
4. **Unaligned Destination Start Address:**
   - Destination address: `0x2001`, `0x2002`, `0x2003`.
   - Verifies first beat byte lane enables (`WSTRB = 4'b1110`, `4'b1100`, `4'b1000`) and barrel shifter realignment.
   - Bins hit: `cg_dma_wr_desc.cp_addr_offset`, `cg_dma_axi_w_master.cp_wstrb_first`.
5. **Partial Final Beat (WSTRB mask):**
   - Transfer ends on a non-word boundary (e.g. 63 bytes).
   - Verifies that final write beat masks out unused upper bytes (`WSTRB = 4'b0111`) so adjacent memory is uncorrupted.
   - Bins hit: `cg_dma_axi_w_master.cp_wstrb_last`.
6. **Memory Write Backpressure:**
   - Memory slave deasserts `AWREADY` or `WREADY` to inject backpressure.
   - Verifies that the DMA throttles `s_axis_write_data_tready` and resumes without dropping beats.

---

### Feature 3: Hardware Robustness & Corner-Case States

#### Objective
Verify that the DMA safely recovers from protocol mismatches and abnormal stream behavior without locking up the bus.

#### Test Scenarios:
1. **Early Stream Termination (Runt Frame) -> `STATE_FINISH_BURST`:**
   - **Scenario:** Descriptor buffer configured for 64 bytes (16 beats, `AWLEN = 15`), but the stream packet unexpectedly asserts `TLAST` after only 8 beats.
   - **Hardware Reaction:** AXI slave already accepted `AWLEN = 15` and requires 16 beats. The DMA enters `STATE_FINISH_BURST`, issues 8 dummy beats with **`WSTRB = 4'b0000`**, and asserts `WLAST` on beat 16.
   - **Verification Check:** Memory is unmodified beyond byte 32. Status reports transferred length = 32 bytes.
   - **Bins hit:** `cg_write_abort.cp_early_tlast`, FSM transition `STATE_WRITE -> STATE_FINISH_BURST`.
2. **Excess Stream Data -> `STATE_DROP_DATA`:**
   - **Scenario:** Descriptor buffer configured for 32 bytes (8 beats), but the stream producer supplies 64 beats before asserting `TLAST`.
   - **Hardware Reaction:** After writing 32 bytes to memory, the DMA stops AXI writes, enters `STATE_DROP_DATA`, keeps `TREADY = 1`, and safely drains the remaining 56 beats until `TLAST`.
   - **Verification Check:** Extra 56 beats are discarded without memory corruption; upstream pipeline is not stalled.
   - **Bins hit:** `cg_write_abort.cp_excess_stream`, FSM transition `STATE_WRITE -> STATE_DROP_DATA`.
3. **Inter-Beat Stream Bubbles:**
   - Ingress stream producer inserts random delays (1 to 5 cycles of `TVALID = 0`) between beats.
   - Verifies DMA holds active burst state and does not generate spurious writes.
   - Bins hit: `cg_axis_wr_stream.cp_inter_beat_delay`.

---

### Feature 4: Bus Error Handling & Propagation

#### Objective
Verify that slave bus errors on the AXI-MM interconnect are captured and reported cleanly in the descriptor completion status.

#### Test Scenarios:
1. **Read Slave Error (`RRESP = SLVERR`):**
   - Memory slave returns `SLVERR` (`2'b10`) on a read data beat.
   - Verifies `m_axis_read_desc_status_error` pulses with error code `4'd4` (`DMA_ERROR_AXI_RD_SLVERR`).
   - Bins hit: `cg_dma_axi_r_master.cp_rresp.slverr`, `cg_dma_rd_desc_status.cp_error.slverr`.
2. **Read Decode Error (`RRESP = DECERR`):**
   - Memory slave returns `DECERR` (`2'b11`) on a read data beat.
   - Verifies `m_axis_read_desc_status_error` pulses with error code `4'd5` (`DMA_ERROR_AXI_RD_DECERR`).
   - Bins hit: `cg_dma_axi_r_master.cp_rresp.decerr`, `cg_dma_rd_desc_status.cp_error.decerr`.
3. **Write Slave Error (`BRESP = SLVERR`):**
   - Memory slave returns `SLVERR` (`2'b10`) on write response.
   - Verifies `m_axis_write_desc_status_error` pulses with error code `4'd6` (`DMA_ERROR_AXI_WR_SLVERR`).
   - Bins hit: `cg_dma_axi_b_master.cp_bresp.slverr`, `cg_dma_wr_desc_status.cp_error.slverr`.
4. **Write Decode Error (`BRESP = DECERR`):**
   - Memory slave returns `DECERR` (`2'b11`) on write response.
   - Verifies `m_axis_write_desc_status_error` pulses with error code `4'd7` (`DMA_ERROR_AXI_WR_DECERR`).
   - Bins hit: `cg_dma_axi_b_master.cp_bresp.decerr`, `cg_dma_wr_desc_status.cp_error.decerr`.

---

## 5. Traceability Matrix (Testcase <-> Feature <-> Bins <-> Code Coverage)

| Testcase Name | Target Feature | Stimulus / Knobs | Key Covergroups & Bins Hit | Target RTL Lines & FSM States |
| :--- | :--- | :--- | :--- | :--- |
| **`dma_sanity_test`** | Base MM2S & S2MM Sanity | 64B transfer, addr 0x1000/0x2000, 16 beats | `cg_dma_rd_desc`, `cg_dma_wr_desc`, `cg_axis_rd_stream`, `cg_axis_wr_stream` | `AXI_STATE_START`, `STATE_START`, `STATE_WRITE` |
| **`dma_burst_slicing_test`** | Multi-burst segmentation | Lengths: 128B, 256B, 1024B | `cg_cross_tier.cross_rd_slicing_len`, `cg_cross_tier.cross_wr_slicing_len` | Loopback transitions: `START -> START` (RD), `WRITE -> START` (WR) |
| **`dma_4k_boundary_test`** | 4KB page boundary clipping | Addr `0x0FE0` and `0x1FE0`, len 64B | `cg_dma_axi_ar_master.cp_4k_cross`, `cg_dma_axi_aw_master.cp_4k_cross` | 4KB clipping branch: `tr_word_count_next = 13'h1000 - (addr & 12'hfff)` |
| **`dma_unaligned_test`** | Barrel shifter byte alignment | Addr offsets: +1, +2, +3 bytes | `cp_addr_offset`, `cp_wstrb_first`, `cp_araddr_align` | Barrel shifter: `shift_axi_rdata`, `shift_axis_tdata`, `ENABLE_UNALIGNED` logic |
| **`dma_partial_beat_test`** | Non-word lengths | Lengths: 1B, 2B, 3B, 15B, 63B | `cp_tkeep_last`, `cp_wstrb_last` | Last beat masks: `m_axis_read_data_tkeep_int`, `m_axi_wstrb_int` |
| **`dma_early_term_test`** | Early stream termination | Desc len: 64B; Stream sends 8 beats + TLAST | `cg_write_abort.cp_early_tlast` | `STATE_WRITE -> STATE_FINISH_BURST`, dummy padding with `WSTRB=0` |
| **`dma_excess_stream_test`** | Excess stream draining | Desc len: 32B; Stream sends 64 beats | `cg_write_abort.cp_excess_stream` | `STATE_WRITE -> STATE_DROP_DATA`, draining until `TLAST` |
| **`dma_backpressure_test`** | Handshake flow control | Random TREADY delays, WREADY stalls | `cp_inter_beat_delay`, `cp_ready_delay` | Skid buffer logic: `out_fifo_half_full_reg`, `m_axi_rready_reg` |
| **`dma_error_inject_test`** | Slave error propagation | Inject SLVERR and DECERR on R and B | `cp_rresp`, `cp_bresp`, `cp_error` | Status mapping: `DMA_ERROR_AXI_RD_SLVERR`, `DMA_ERROR_AXI_WR_SLVERR` |
| **`dma_random_stress_test`**| Random stress & concurrency | Random lengths (1-1024B), random addrs | Hits all cross-coverage bins and toggle coverage | Exercises entire RTL datapath under high pipeline load |

---

## 6. Verification Sign-Off Criteria

A simulation run is considered **Sign-Off Complete (Tape-Out Ready)** only when all of the following gates are met:

1. **Functional Coverage Gate:**
   - **100% Coverage** achieved across all 13 Covergroups in `dma_coverage.sv`.
   - **Zero Uncovered Bins** (no illegal bins hit, all crosses populated).
2. **Code Coverage Gates (Measured via Cadence IMC):**
   - **Line / Statement Coverage:** $\ge 98\%$ (all operational RTL lines executed).
   - **Branch / Decision Coverage:** $\ge 95\%$ (all true/false branch decisions taken).
   - **FSM State Coverage:** **100%** (all 2 states in `axi_state`, 2 in `axis_state`, 5 in Write FSM visited).
   - **FSM Transition Coverage:** **100%** (all defined state transitions exercised).
   - **Expression / Condition Coverage:** $\ge 90\%$.
   - **Toggle Coverage:** $\ge 90\%$ on all interface bus ports and internal registers.
3. **Simulation Status:**
   - **0 UVM Errors** (`uvm_report_server::get_severity_count(UVM_ERROR) == 0`).
   - **0 UVM Warnings / Fatals**.
   - Scoreboard data integrity verification passes with zero byte mismatches.
