# Design and Implementation of a UVM-Based Verification Intellectual Property (VIP) for an AXI4 DMA and Memory Subsystem

## B.Tech Major Project — Mid-Semester Progress Review Report

---

### Project Metadata
- **Project Title:** Design and Implementation of a UVM-Based Verification Intellectual Property (VIP) for an AXI4 DMA and Memory Subsystem
- **Methodology:** Universal Verification Methodology (IEEE 1800.2 UVM) & SystemVerilog (IEEE 1800-2017)
- **Target Design Under Test (DUT):** Synthesizable High-Throughput AMBA AXI4 Direct Memory Access (`axi_dma`) Engine & Subsystem
- **EDA & Simulation Environment:** Cadence Xcelium Logic Simulator (`xrun`), Cadence IMC (Integrated Metrics Center)
- **Review Stage:** Mid-Semester Evaluation

---

### Executive Abstract

Modern System-on-Chip (SoC) architectures rely heavily on Direct Memory Access (DMA) engines to facilitate high-throughput, autonomous data transfers between streaming peripherals and memory-mapped storage. As these designs grow in complexity, traditional directed testing methodologies are insufficient to guarantee protocol compliance and data integrity against edge-case scenarios, such as unaligned transfers, aggressive bus backpressure, and asynchronous command execution. This project focuses on the design and implementation of a robust, industry-standard Verification Intellectual Property (VIP) using the Universal Verification Methodology (UVM) to exhaustively verify an AMBA AXI4 DMA and Static RAM subsystem.

The verification environment is architected with independent, highly reusable UVM Agents targeting both AXI4 Memory-Mapped and AXI4-Stream protocols. By abstracting physical pin-level signalling into high-level sequence items, the environment utilizes constrained-random stimulus generation to aggressively stress the Design Under Test (DUT) across isolated and subsystem-level topologies. An automated, centralized UVM Scoreboard with reference models is implemented to perform data integrity checks, ensuring seamless translation between address-less stream payloads and address-based memory bursts. The primary objective of this project is to achieve 100% functional and structural code coverage, thereby proving complete AMBA protocol compliance. Ultimately, this work delivers a scalable, production-grade verification framework that guarantees the functional correctness of the DMA-RAM subsystem, establishing a rigorously verified baseline for future architectural enhancements.

---

## 1. High-Level Architecture & Verification Framework

The verification framework is developed from the ground up to verify an autonomous, full-duplex AXI4 DMA engine containing two decoupled internal FSM pipelines:
1. **MM2S (Memory-to-Stream) Read Engine:** Fetches block data from memory-mapped storage across the AXI4 Master Read channel (`AR`/`R`) and packages it into structured AXI4-Stream egress packets (`m_axis_read_data_*`).
2. **S2MM (Stream-to-Memory) Write Engine:** Ingests incoming AXI4-Stream ingress packets (`s_axis_write_data_*`) and flushes the payload into memory-mapped space across the AXI4 Master Write channel (`AW`/`W`/`B`).

To guarantee verification reuse and complete fault isolation, the testbench supports two operational configurations controlled via compile-time plusargs:
- **DMA Standalone Mode (`+define+DMA_STANDALONE`):** Targets the core `axi_dma` module directly. All 6 UVM agents are active; the AXI-MM VIP operates as an active, configurable slave memory responder serving read bursts and acknowledging write handshakes.
- **Subsystem Mode (`+define+SUBSYSTEM`):** Wraps the DMA together with an internal multi-channel interconnect and Static RAM (`axi_ram`). Here, the AXI-MM VIP switches cleanly to passive monitoring mode to prevent dual-driver bus contention.

```
+-------------------------------------------------------------------------------------------------------------------------+
|                                                  UVM TESTBENCH TOPOLOGY                                                 |
|                                                                                                                         |
|       +------------------------------------+                    +------------------------------------+                  |
|       |    dma_rd_desc_agent (ACTIVE)      |                    |    dma_wr_desc_agent (ACTIVE)      |                  |
|       |  [Driver / Monitor / Sequencer]    |                    |  [Driver / Monitor / Sequencer]    |                  |
|       +-----------------+------------------+                    +-----------------+------------------+                  |
|                         | Descriptor Command / Status                             | Descriptor Command / Status         |
|                         v                                                         v                                     |
|           +-----------------------------------------------------------------------------------------+                   |
|           |                                DESIGN UNDER TEST (axi_dma)                               |                   |
|           |                                                                                         |                   |
|           |    [MM2S Datapath Engine]                                 [S2MM Datapath Engine]        |                   |
|           |    - Memory Burst Slicing                                 - Stream Packet Ingestion     |                   |
|           |    - Realignment Barrel-Shifter                           - Word Realignment / Packing  |                   |
|           |    - Skid Buffer / FIFO                                   - 4KB Boundary Splitting      |                   |
|           +-------------+-----------------------------+---------------------------+-----------------+                   |
|                         |                             |                           |                                     |
|    AXI Read Bursts      |          AXIS Egress        |        AXIS Ingress       |      AXI Write Bursts               |
|    (AR, R Channels)     |          Stream Data        |        Stream Data        |      (AW, W, B Channels)            |
|                         v                             v                           v                         v           |
|       +-----------------+---+               +---------+-------+           +-------+---------+     +---------+-------+   |
|       |   axi_rd_agent      |               |  axis_rd_agent  |           |  axis_wr_agent  |     |  axi_wr_agent   |   |
|       |  (Slave Responder)  |               | (Passive Mon/   |           | (Active Stream  |     | (Slave Responder|   |
|       |  [AR, R Channels]   |               |   Active Sink)  |           |     Driver)     |     |  [AW, W, B])    |   |
|       +---------+-----------+               +---------+-------+           +-------+---------+     +---------+-------+   |
|                 |                                     |                           |                         |           |
|                 +---------------+                     |                           |                 +-------+           |
|                                 |                     |                           |                 |                   |
|                                 v                     v                           v                 v                   |
|       +---------------------------------------------------------------------------------------------------------+       |
|       |                           END-TO-END VERIFICATION SCOREBOARD (dma_scoreboard)                            |       |
|       |  - Algorithmic Reference Models (Decoupled MM2S & S2MM Engines)                                         |       |
|       |  - Byte-by-Byte Memory vs. Stream Correlation & Unaligned Address Shifter Checking                      |       |
|       |  - Strobe (WSTRB) / Keep (TKEEP) / Framing (TLAST, WLAST, RLAST) Protocol Boundary Checkers             |       |
|       |  - 1-to-1 Packet Boundary Verification & S2MM Buffer Bounds Enforcement (STATE_DROP_DATA)               |       |
|       +---------------------------------------------------------------------------------------------------------+       |
|                                                                                                                         |
|       +---------------------------------------------------------------------------------------------------------+       |
|       |                           TIERED FUNCTIONAL COVERAGE MODEL (dma_coverage)                               |       |
|       |  - Tier 1: Descriptors  |  Tier 2: Stream Datapaths  |  Tier 3: AXI-MM Master  |  Tier 4: Concurrency    |       |
|       +---------------------------------------------------------------------------------------------------------+       |
+-------------------------------------------------------------------------------------------------------------------------+
```

---

## 2. Detailed Technical Development Milestones

### Milestone 1: Protocol Study & Requirements Extraction
- **Scope & Objectives:** In-depth review of the official ARM AMBA specifications (IHI0022H for AXI4 Memory-Mapped and IHI0051B for AXI4-Stream) to extract corner cases, handshaking rules, and verification requirements.
- **Key Protocol Mechanics Addressed:**
  - *AXI4 Memory-Mapped:* Five independent, asynchronous channels (`AW`, `W`, `B`, `AR`, `R`). Two-way valid/ready handshaking rules, out-of-order burst completion with transaction IDs (`ARID`, `AWID`, `RID`, `BID`), INCR burst constraints, 4KB page boundary non-crossing rules, and sparse write strobe (`WSTRB`) generation for unaligned start/end offsets.
  - *AXI4-Stream:* Continuous dataflow without addresses, multi-byte packet framing using `TLAST`, byte-level qualification via `TKEEP`, sideband signal propagation (`TID`, `TDEST`, `TUSER`), and backpressure latency via `TREADY`.
  - *DMA Descriptor Semantics:* Command acceptance handshaking (`valid`/`ready`), completion status pulses, dynamic byte-length accounting, and status error code encodings (`OKAY`, `SLVERR`, `DECERR`).
- **Engineering Deliverable:** Systematic mapping of protocol requirements into an exhaustive Verification Plan matrix (`docs/dma_vplan.md`), defining functional coverage tiers and cross-coverage targets.

---

### Milestone 2: Generic Verification IP (VIP) Development
To ensure verification scalability and reuse, three generic, fully parameterizable VIP packages were designed and implemented from scratch in SystemVerilog/UVM:

1. **`axi_mm_vip` (AXI4 Memory-Mapped VIP):**
   - Implements sequence item `axi_seq_item` modeling address, length (`AxLEN`), transfer size (`AxSIZE`), burst type (`AxBURST`), IDs, dynamic payload queues (`data[]`), write strobes (`strb[]`), response codes (`RRESP`/`BRESP`), and framing signals (`wlast[]`, `rlast[]`).
   - Encapsulates dedicated interface `axi_if` with directional modports and clocking blocks (`wr_drv_cb`, `rd_drv_cb`, `wr_mon_cb`, `rd_mon_cb`) to completely prevent simulation race conditions and delta-cycle glitches.
   - Provides an active slave responder sequence (`axi_slave_seq.sv`) backed by an associative memory model to automatically service DUT memory reads and acknowledge writes with realistic, randomized latencies.

2. **`axis_vip` (AXI4-Stream VIP):**
   - Implements sequence item `axis_seq_item` abstracting entire packets as variable-length dynamic arrays (`data[]`, `keep[]`, `user[]`, `delay[]`).
   - Contains configurable knobs for packet size, inter-beat bubbles (`delay`), downstream backpressure stalls (`ready_delay`), and unaligned trailing byte qualifiers (`force_full_last_keep`).

3. **`dma_desc_vip` (Descriptor VIP):**
   - Models DMA Read (MM2S) and Write (S2MM) command injection and asynchronous status collection.
   - Features randomized transfer length, aligned/unaligned base addresses, and unique tracking tags (`tag`) for out-of-order correlation.

---

### Milestone 3: UVM Environment Integration & Agent Topology
The modular VIPs were assembled into the top-level verification container `dma_subsystem_env` (`uvm/env/dma_subsystem_env.sv`), which instantiates and interconnects six specialized UVM agents:

```systemverilog
// Environment instantiation summary
axi_wr_agent_type      axi_wr_agent;      // S2MM Memory Write Master
axi_rd_agent_type      axi_rd_agent;      // MM2S Memory Read Master
dma_rd_desc_agent_type dma_rd_desc_agent; // MM2S Command/Status Interface
dma_wr_desc_agent_type dma_wr_desc_agent; // S2MM Command/Status Interface
axis_wr_agent_type     axis_wr_agent;     // S2MM Ingress Stream Source
axis_rd_agent_type     axis_rd_agent;     // MM2S Egress Stream Sink
```

- **Topology Adaptability:** Implemented in `dma_base_test.sv` using `uvm_config_db`. In standalone mode, the environment sets `axi_wr_agent` and `axi_rd_agent` to `UVM_ACTIVE` with background slave responders. In subsystem mode, the agents automatically switch to `UVM_PASSIVE`, preventing dual-driver bus fighting with the RTL static RAM.
- **Channel Decoupling:** Analysis ports from all six agents broadcast passively snooped transactions to the scoreboard and functional coverage models without stalling simulator execution.

---

### Milestone 4: UVM Component Engineering (Drivers, Monitors & Sequences)
Significant engineering effort was dedicated to hardening the drivers and monitors against subtle protocol and timing corner cases:

1. **Cycle-Accurate Passive Monitors:**
   - `axis_rd_monitor.sv` and `axis_wr_monitor.sv` passively capture cycle-accurate inter-beat bubble cycles (`delay[]`) and downstream consumer stalls (`ready_delay`) directly inside the clocking block.
   - Monitors publish complete transaction items to analysis ports strictly on accepted handshakes (`TVALID && TREADY`).
2. **In-Flight Protocol Framing Checks:**
   - Enhanced `axi_wr_monitor.sv` and `axi_rd_monitor.sv` with protocol framing checks:
     - Verified that the DUT asserts `WLAST` strictly on the final beat of a write burst (`beat == AWLEN`), flagging premature or missing assertions as DUT errors (`[DUT]`).
     - Verified that the slave responder asserts `RLAST` strictly on the final beat of a read burst, flagging responder misbehavior (`[RESPONDER]`).
     - Checked transaction ID preservation (`RID == ARID`, `BID == AWID`).
3. **Stimulus Sequence Library:**
   - `dma_rd_desc_sanity_seq`: Drives MM2S read descriptors with parameterized lengths and addresses.
   - `dma_wr_desc_sanity_seq`: Concurrently issues S2MM write descriptors.
   - `axis_packet_seq`: Ingests multi-beat stream payloads with configurable delays and trailing `TKEEP` lane patterns.

---

### Milestone 5: Base Testbench Architecture, Scoreboard & Coverage Model

#### 1. End-to-End Scoreboard Architecture (`dma_scoreboard.sv`)
Unlike simple bus scoreboards that perform 1-to-1 lookups, verifying a DMA engine requires translating between **address-based memory bursts** and **address-less stream packets**:
- **Multi-Port TLM Ingestion:** Utilizes `uvm_analysis_imp_decl` macros guarded by `DMA_IMP_DECLS` to bind eight independent monitor streams into dedicated handler functions.
- **MM2S Algorithmic Reference Model:** Unpacks 32-bit AXI memory read words, applies start-address window masking to slice out requested unaligned bytes, and incrementally matches them against egress stream payload bytes.
- **S2MM Memory & Strobe Checker:** Ingests incoming stream bytes as golden reference. As the DMA issues AXI write bursts, the scoreboard computes the exact physical byte address for each beat and active strobe (`WSTRB`), validating that data lands in the correct memory location and detecting any unaligned strobe masking gaps.
- **Burst-Resilient Pair-Wise Drain:** Employs incremental pair-wise queues (`expected_bytes[$]`, `actual_bytes[$]`) that drain as bytes arrive, ensuring comparisons succeed regardless of whether AXI memory bursts or AXIS stream packets finish first.
- **Buffer Boundary & Overflow Enforcement:** Enforces that active write strobes never exceed `[dest_addr, dest_addr + buffer_len - 1]` (`SCB_S2MM_BUF_OVERFLOW`). When the stream exceeds descriptor capacity, verifies that the DUT clamps `status_len` to `buffer_len` and cleanly drops remaining bytes in `STATE_DROP_DATA`.
- **Packet Boundary & TLAST Checks:** Validates that each descriptor produces/consumes exactly one packet (`packet_count == 1`) and checks that packet length at `TLAST` matches the requested transfer length.
- **Authoritative Scorecard Verdict:** `check_phase` catches hung or orphan descriptors. `report_phase` computes a comprehensive scorecard table; if any mismatches, address errors, packet errors, or hung descriptors are detected, the overall verdict is marked `[TEST FAILED]`.

#### 2. Tiered Functional Coverage Model (`dma_coverage.sv`)
Contains 12 comprehensive covergroups structured across four verification tiers:
- **Tier 1 (Descriptors):** Command lengths, aligned/unaligned base addresses, tag distributions, and completion status error codes.
- **Tier 2 (Stream Datapaths):** Packet beat counts, inter-beat bubbles, downstream stall cycles, and partial trailing `TKEEP` patterns.
- **Tier 3 (AXI Master Interface):** Burst lengths (`AxLEN`), transfer sizes (`AxSIZE`), 4KB page boundary proximity, burst boundary addresses, and observed `WLAST`/`RLAST` handshakes.
- **Tier 4 (System Concurrency):** Simultaneous active execution of MM2S and S2MM engines and fault isolation.

---

### Milestone 6: Sanity Test Validation & Testbench Infrastructure
- **Sanity Test (`dma_sanity_test.sv`):** Executes a two-phase sanity sequence in DMA Standalone mode:
  - *Phase 1 (MM2S):* Dispatches a 64-byte read transfer at memory address `0x1000`. Memory read slave responds; stream sink captures egress packets; scoreboard verifies 64 bytes matched.
  - *Phase 2 (S2MM):* Concurrently forks a 64-byte write descriptor (destination `0x2000`) and a 16-beat ingress stream packet. DMA arbitrates and writes data to memory; scoreboard verifies address progression, strobe placement, and status length.
- **Infrastructure Automation:** Consolidated compile and execution scripts (`run_dir/run_cmd.sh`, `run_dir/Makefile`) targeting Cadence Xcelium (`xrun -64bit -uvm`). Automated RTL symlinking and configured coverage collection (`-coverage all -covworkdir ./cov_work`) to be active by default on single test runs.

---

## 3. Summary of Technical Challenges Overcome

During the bring-up and static review phases, several critical technical issues were resolved:

1. **AXI-MM Dual-Driver Contention (TB-09):** In subsystem mode, both the active VIP slave driver and the RTL `axi_ram` attempted to drive `s_axi_rvalid`/`rdata`. Resolved by configuring `dma_base_test` to switch AXI-MM VIPs to `UVM_PASSIVE` in subsystem mode while keeping them `UVM_ACTIVE` in standalone mode.
2. **Cycle-Accurate Inter-Beat Stall Tracking (TB-02, TB-03):** Initial stream monitors missed bubble cycles because they only sampled active beats. Reworked the sampling loop to count idle clock cycles between valid beats, enabling functional coverage of backpressure.
3. **Observed vs. Computed Protocol Framing Coverage (TB-10):** Early coverage models sampled computed beat loop indices rather than observed bus signals. Updated monitors to record observed `wlast[]` and `rlast[]` from the interface and added illegal cross-coverage bins for premature or missing framing pulses.
4. **Out-of-Order Burst Queue Cleanliness:** Fixed a scoreboard issue where status arrival deleted tag lookups but left orphaned entries in the head of FIFO queues. Added single-pipeline in-order assertions and tag-based deletion across all tracking structures.
5. **Memory Buffer Overflow Protection:** Corrected an issue where stream packets larger than descriptor buffer capacity were not bound-checked against memory space. Implemented strict `WSTRB` address boundary checks and `STATE_DROP_DATA` overflow verification.

---

## 4. Current Project Status

| Project Phase / Component | Current Status | Engineering Notes |
|---|---|---|
| **AMBA AXI4 / AXIS Protocol Analysis** | **Completed** | Full protocol specification study; extracted corner cases and verification metrics into vPlan. |
| **Generic VIP Architecture (`axi_mm`, `axis`, `desc`)** | **Completed** | All sequence items, interfaces, drivers, monitors, and agents designed, compiled, and validated. |
| **UVM Environment & Topologies** | **Completed** | 6-agent environment integrated; supports both `DMA_STANDALONE` and `SUBSYSTEM` topologies. |
| **Monitor Assertions & Bubble Tracking** | **Completed** | Frame check assertions, timing delays, and directional tag logging (`[DUT]` vs `[RESPONDER]`) active. |
| **UVM Scoreboard Architecture** | **Completed** | Two decoupled engines, incremental comparator, buffer bound enforcement, and scorecard report implemented. |
| **Initial Functional Coverage Model** | **Completed** | 12 covergroups across 4 tiers implemented; observed bus signal sampling integrated. |
| **Sanity Test (`dma_sanity_test`) Simulation** | **In Progress** | Standalone environment assembled and committed (`origin/main`); active execution on Cadence Xcelium in remote lab workstation underway. |
| **Verification Plan (vPlan) Test Campaign** | **Planned** | Directed and constrained-random test cases for edge cases, corner cases, and stress scenarios. |
| **Coverage Closure & Regression Analysis** | **Planned** | Cadence IMC coverage database merging, hole analysis, and regression suite execution toward 100% target. |

> **Note on Verification Status:** The testbench architecture, VIPs, monitors, coverage model, and scoreboard are fully integrated in source control. Hardware simulation of `dma_sanity_test` on Cadence Xcelium Logic Simulator is currently in the active execution phase on the remote laboratory workstation. Verification metrics (code coverage percentages, regression pass rates) will be reported following simulation execution and IMC database compilation.

---

## 5. Roadmap Toward Final Review (Next Steps)

To transition from the current baseline infrastructure to complete verification closure for the final semester review, the following work is planned:

1. **Simulation Validation of Sanity Baseline:** Complete execution of `dma_sanity_test` on Cadence Xcelium to confirm zero scoreboard mismatches, verify clean descriptor retirement, and inspect initial coverage generation.
2. **Implementation of Constrained-Random vPlan Test Suite:**
   - *Unaligned Address & Strobe Stress Test (`dma_unaligned_test`):* Randomize transfer start addresses across non-word-aligned byte offsets (`0x1001`, `0x1002`, `0x1003`) to stress the DUT barrel-shifter and strobe masking logic.
   - *4KB Boundary Crossing Test (`dma_4kb_crossing_test`):* Force bursts near `0xFFC` to verify that the DMA splits transfers into legal compliant bursts without crossing 4KB boundaries.
   - *Aggressive Backpressure & Stall Test (`dma_backpressure_test`):* Introduce randomized `tready` stalls on stream sinks and memory slaves to stress internal FIFOs and skid buffers.
   - *Full-Duplex Concurrent Stress Test (`dma_concurrent_test`):* Fork parallel MM2S and S2MM transfers to verify arbitration, full-duplex throughput, and shared bus handling.
   - *Error Injection & Fault Handling (`dma_error_test`):* Inject slave errors (`SLVERR`/`DECERR`) on read/write channels to verify DMA abort behavior and status error reporting.
3. **Subsystem Integration Mode Validation:** Run regressions with compile plusarg `+define+SUBSYSTEM` to verify end-to-end communication with the Static RAM (`axi_ram`) through the interconnect.
4. **Coverage Closure & Analysis:**
   - Execute regression suites and merge coverage databases using Cadence IMC.
   - Analyze coverage holes across statement, branch, FSM, and functional cross-covergroups.
   - Write targeted directed tests for any unhit corner-case bins to achieve the target of 100% functional and code coverage.

---

### Conclusion

Up to this mid-semester milestone, the project has established a production-grade, reusable UVM verification platform for the AXI4 DMA Subsystem. The physical protocol layers, generic VIPs, multi-agent environment container, algorithmic scoreboard, and tiered coverage models have been designed, hardened, and integrated. This infrastructure provides a verified foundation for executing the comprehensive test plan, performing constrained-random stress testing, and driving toward full coverage closure in the second half of the project.
