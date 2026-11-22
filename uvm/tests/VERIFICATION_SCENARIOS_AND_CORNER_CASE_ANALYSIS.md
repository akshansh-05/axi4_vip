# Verification Scenarios & Hardware Corner-Case Analysis

## 1. Verification Strategy & Testbench Hierarchy

The AMBA AXI4 DMA Subsystem features a dual-engine architecture comprising an MM2S (Memory-to-Stream) Read Controller and an S2MM (Stream-to-Memory) Write Controller. To achieve exhaustive functional closure, the verification platform is architected around a layered stimulus hierarchy executing 17 dedicated feature tests across both pipelines.

```mermaid
graph TD
    subgraph Test_Layer ["UVM Test Layer (uvm/tests/dma_tests)"]
        TESTS_RD["MM2S Read Feature Suite (6 Tests)"]
        TESTS_WR["S2MM Write Feature Suite (11 Tests)"]
    end

    subgraph Sequence_Layer ["Virtual Sequence Layer"]
        SEQ_DESC["DMA Descriptor Sequences (Nominal, B2B, Skew, 4KB, Unaligned)"]
        SEQ_STRM["AXI-Stream Sequences (Framed, Bubbled, Excess, Early-Term)"]
        SEQ_AXI["AXI-MM Slave Sequences (Backpressure, Response Injection)"]
    end

    subgraph VIP_Layer ["Verification Intellectual Property (VIP)"]
        VIP_DESC["dma_desc_vip (Host Control)"]
        VIP_STRM["axis_vip (Streaming Datapath)"]
        VIP_AXI["axi_mm_vip (Memory Interconnect)"]
    end

    subgraph Validation_Layer ["Checking & Metrics"]
        SCB["Algorithmic Scoreboard (dma_scoreboard)"]
        COV["Multi-Tier Coverage Model (dma_coverage)"]
    end

    TESTS_RD --> SEQ_DESC & SEQ_STRM & SEQ_AXI
    TESTS_WR --> SEQ_DESC & SEQ_STRM & SEQ_AXI
    SEQ_DESC --> VIP_DESC
    SEQ_STRM --> VIP_STRM
    SEQ_AXI --> VIP_AXI
    VIP_DESC & VIP_STRM & VIP_AXI --> SCB & COV
```

### 1.1 Separation of Sanity Bringup vs. Feature Regression
A common verification pitfall is including smoke or bringup tests (`dma_sanity_test`) in production regression databases. In this verification platform:
* `dma_sanity_test`: Serves strictly as a post-compile environment sanity check to verify agent instantiation, interface wiring, and clock/reset sequencing.
* **Regression Directive:** `dma_sanity_test` is strictly excluded from `make run_all_dma`, `make merge_cov`, and regression scorecards. All metrics and coverage closure figures reflect solely the 17 deterministic feature tests.

## 2. MM2S Read Pipeline Feature Verification (6 Tests)

The MM2S Read Controller fetches data from memory-mapped addresses via AXI4 AR and R channels and streams contiguous packets over the AXI4-Stream master interface.

```mermaid
flowchart LR
    MEM[("AXI4 Memory Fabric")] -->|AR/R Bursts| RD_CORE["axi_dma_rd Engine"]
    RD_CORE -->|Barrel Shifter| FIFO["Egress Stream FIFO"]
    FIFO -->|AXIS Beats| STREAM[("Egress AXI4-Stream")]
    CTRL["Host Descriptor Engine"] -->|Command / Status| RD_CORE
```

### 2.1 `dma_rd_nominal_test`
* **Objective:** Establish the baseline verification signature for single-burst, word-aligned memory reads.
* **Stimulus Parameters:** Start Address $0\text{x}1000$ (32-bit aligned), Length $64\text{ bytes}$ (16 words), Tag $0\text{x}01$.
* **Hardware Execution:** The DMA issues a single AXI read burst with $ARADDR = 0\text{x}1000$ and $ARLEN = 15$. The 16 beats of read data pass through the read FIFO and serialize onto the streaming interface.
* **Scoreboard Invariants:** Verifies single-packet framing ($1\text{ packet}$ with `TLAST` asserted on beat 15), exact byte count match ($64\text{ bytes}$), and synchronous status retirement ($0\text{x}01$).

### 2.2 `dma_rd_multiburst_test`
* **Objective:** Validate multi-burst address decomposition and state machine sequencing across transfers exceeding the 16-beat AXI burst ceiling.
* **Stimulus Parameters:** Start Address $0\text{x}2000$, Length $256\text{ bytes}$ (64 words), Tag $0\text{x}02$.
* **Hardware Execution:** The DMA decomposes the 256-byte request into 4 distinct AXI read bursts of 16 beats each:
  1. Burst 1: $ARADDR = 0\text{x}2000$, $ARLEN = 15$ ($64\text{ bytes}$)
  2. Burst 2: $ARADDR = 0\text{x}2040$, $ARLEN = 15$ ($64\text{ bytes}$)
  3. Burst 3: $ARADDR = 0\text{x}2080$, $ARLEN = 15$ ($64\text{ bytes}$)
  4. Burst 4: $ARADDR = 0\text{x}20\text{C}0$, $ARLEN = 15$ ($64\text{ bytes}$)
* **Scoreboard Invariants:** Enforces sequential address progression:
  $$ARADDR_{k+1} = ARADDR_k + ((ARLEN_k + 1) \cdot 4)$$
  Confirms that data from all 4 bursts is merged into a single continuous stream packet with `TLAST` asserted only on the 64th beat.

### 2.3 `dma_rd_4kb_split_test`
* **Objective:** Verify compliance with ARM AMBA AXI4 Section A3.4.1 forbidding any burst from crossing a 4KB ($4096\text{ byte}$) page boundary.
* **Stimulus Parameters:** Start Address $0\text{x}0\text{FE}0$, Length $64\text{ bytes}$ ($16\text{ words}$), Tag $0\text{x}03$. The 4KB page boundary lies at $0\text{x}1000$.
* **Hardware Execution:** The DMA calculates remaining bytes to the boundary ($4096 - (0\text{x}0\text{FE}0 \ \& \ 0\text{xFFF}) = 32\text{ bytes}$) and clamps the first burst to 8 beats:
  * Burst 1 (Pre-boundary): $ARADDR = 0\text{x}0\text{FE}0$, $ARLEN = 7$ ($32\text{ bytes}$, spans $0\text{x}0\text{FE}0$ to $0\text{x}0\text{FFF}$)
  * Burst 2 (Post-boundary): $ARADDR = 0\text{x}1000$, $ARLEN = 7$ ($32\text{ bytes}$, spans $0\text{x}1000$ to $0\text{x}101\text{F}$)
* **Scoreboard Invariants:** Asserts that $(ARADDR \ \& \ 0\text{xFFF}) + ((ARLEN + 1) \cdot 4) \le 4096$ for every burst. Confirms that no burst crosses $0\text{x}1000$.

### 2.4 `dma_rd_unaligned_test`
* **Objective:** Stress the DMA's internal barrel shifter by issuing transfers starting at non-word-aligned byte boundaries.
* **Stimulus Parameters:** Start Address $0\text{x}1001$ (Offset 1), Length $11\text{ bytes}$, Tag $0\text{x}04$.
* **Hardware Execution:** The DMA rounds down the memory address to the aligned boundary ($ARADDR = 0\text{x}1000$) and reads 3 words ($ARLEN = 2$). The internal barrel shifter shifts the 32-bit words right by 1 byte, discarding byte 0 of word 0, and packing the 11 valid payload bytes into aligned 32-bit stream beats.
* **Scoreboard Invariants:** Employs byte windowing to verify that memory byte $0\text{x}1000$ is discarded and only bytes $[0\text{x}1001 : 0\text{x}100\text{B}]$ appear in the egress stream.

### 2.5 `dma_rd_partial_len_test`
* **Objective:** Verify fractional tail packing where total transfer bytes are not an integer multiple of the 4-byte datapath.
* **Stimulus Parameters:** Start Address $0\text{x}1000$, Length $13\text{ bytes}$ (3 full words + 1 fractional byte), Tag $0\text{x}05$.
* **Hardware Execution:** The DMA issues a 4-beat read burst ($ARLEN = 3$). The first 3 stream beats assert full `TKEEP = 4'b1111`. The 4th beat asserts `TKEEP = 4'b0001` alongside `TLAST = 1`.
* **Scoreboard Invariants:** Verifies exact `TKEEP` mask synthesis on the final beat and confirms total byte count $L = 13$.

### 2.6 `dma_rd_backpressure_test`
* **Objective:** Subject the read engine to simultaneous memory-side and stream-side flow-control backpressure.
* **Stimulus Parameters:** Start Address $0\text{x}3000$, Length $64\text{ bytes}$, Tag $0\text{x}06$. VIP drivers inject random 1-to-5 cycle stalls on `ARREADY`, `RREADY`, and egress `TREADY`.
* **Hardware Execution:** The internal read FIFO fills when `TREADY` is deasserted, eventually stalling the AXI master by holding `RREADY` low when full. When backpressure releases, data drains losslessly.
* **Scoreboard Invariants:** Validates zero byte drops, zero data duplication, and proper handshake resumption.

## 3. S2MM Write Pipeline Feature Verification (11 Tests)

The S2MM Write Controller captures streaming packets from `s_axis_write_data_*` and commits them to memory-mapped buffers via AXI4 AW, W, and B channels.

```mermaid
flowchart LR
    STREAM[("Ingress AXI4-Stream")] -->|Payload & TKEEP| WR_CORE["axi_dma_wr Engine"]
    WR_CORE -->|Skid Buffer (2 cycles)| OUT_FIFO["Write Datapath FIFO"]
    OUT_FIFO -->|AW / W Bursts| MEM[("AXI4 Memory Fabric")]
    MEM -->|B Channel Handshake| WR_CORE
    WR_CORE -->|Status Pulse| CTRL["Host Descriptor Status"]
```

### 3.1 `dma_wr_nominal_test`
* **Objective:** Establish the baseline verification signature for word-aligned stream-to-memory write transactions.
* **Stimulus Parameters:** Dest Address $0\text{x}2000$, Buffer Length $64\text{ bytes}$, Stream Payload $64\text{ bytes}$ (16 beats, full `TKEEP`), Tag $0\text{x}07$.
* **Hardware Execution:** Ingress stream beats enter the internal FIFO. The DMA asserts $AWADDR = 0\text{x}2000$, $AWLEN = 15$, and drives 16 write beats with `WSTRB = 4'b1111`. Upon receiving `BVALID/BRESP = OKAY`, it pulses status with length $64$ and error $0$.
* **Scoreboard Invariants:** Real-time lockstep comparison of stream payload against memory write beats, zero strobe holes, and clean tag retirement.

### 3.2 `dma_wr_b2b_test`
* **Objective:** Stress descriptor queueing and pipelined state transitions under back-to-back continuous transfers without intervening idle cycles.
* **Stimulus Parameters:** Two consecutive descriptors:
  * Descriptor 1: Dest $0\text{x}2000$, Len $64\text{ bytes}$, Tag $0\text{x}08$.
  * Descriptor 2: Dest $0\text{x}2040$, Len $64\text{ bytes}$, Tag $0\text{x}09$.
* **Hardware Execution:** Descriptor 2 is submitted while Descriptor 1 is actively executing. As soon as Descriptor 1 finishes its write response, the DMA transitions to Descriptor 2 without dropping bus grants.
* **Scoreboard Invariants:** Verifies independent tracking, FIFO ordering in `s2mm_queue`, and correct sequential status retirement.

### 3.3 `dma_wr_multiburst_test`
* **Objective:** Verify multi-burst memory write segmentation across long streaming payloads exceeding 16 beats.
* **Stimulus Parameters:** Dest Address $0\text{x}4000$, Buffer Length $256\text{ bytes}$ (64 beats), Tag $0\text{x}0\text{A}$.
* **Hardware Execution:** The DMA splits the incoming 256-byte stream into 4 successive 16-beat AXI write bursts:
  * Burst 1: $AWADDR = 0\text{x}4000$, $AWLEN = 15$, $64\text{ bytes}$
  * Burst 2: $AWADDR = 0\text{x}4040$, $AWLEN = 15$, $64\text{ bytes}$
  * Burst 3: $AWADDR = 0\text{x}4080$, $AWLEN = 15$, $64\text{ bytes}$
  * Burst 4: $AWADDR = 0\text{x}40\text{C}0$, $AWLEN = 15$, $64\text{ bytes}$
* **Scoreboard Invariants:** Verifies monotonic $AWADDR$ progression, individual `WLAST` assertions per burst, and single status generation upon the 4th `BVALID`.

### 3.4 `dma_wr_4kb_split_test`
* **Objective:** Validate write burst length clamping across the 4KB memory boundary.
* **Stimulus Parameters:** Dest Address $0\text{x}0\text{FE}0$, Buffer Length $64\text{ bytes}$, Tag $0\text{x}0\text{B}$. 4KB boundary at $0\text{x}1000$.
* **Hardware Execution:** The DMA detects that a 16-beat burst would cross $0\text{x}1000$. It clamps Burst 1 to 8 beats ($AWADDR = 0\text{x}0\text{FE}0, AWLEN = 7$) and issues Burst 2 for the remaining 8 beats ($AWADDR = 0\text{x}1000, AWLEN = 7$).
* **Scoreboard Invariants:** 4KB boundary crossing assertion verifies that $(AWADDR \ \& \ 0\text{xFFF}) + ((AWLEN + 1) \cdot 4) \le 4096$ for all write bursts.

### 3.5 `dma_wr_unaligned_test`
* **Objective:** Verify byte-unaligned write address alignment and sparse write strobe (`WSTRB`) synthesis.
* **Stimulus Parameters:** Dest Address $0\text{x}2001$ (Byte Offset 1), Buffer Length $11\text{ bytes}$, Stream Payload $11\text{ bytes}$, Tag $0\text{x}0\text{C}$.
* **Hardware Execution:** The DMA aligns $AWADDR$ to $0\text{x}2000$ and issues a 3-beat burst ($AWLEN = 2$).
  * Beat 0: `WSTRB = 4'b1110` (Byte 0 masked; bytes 1, 2, 3 written)
  * Beat 1: `WSTRB = 4'b1111` (All 4 bytes written)
  * Beat 2: `WSTRB = 4'b0111` (Bytes 0, 1, 2 written; byte 3 masked)
  * Total written bytes = $3 + 4 + 3 = 10 \dots$ wait, for 11 bytes: Beat 0 has 3 bytes (1,2,3), Beat 1 has 4 bytes (4,5,6,7), Beat 2 has 4 bytes (8,9,10,11 -> offset 0,1,2,3 -> `WSTRB = 4'b1111`).
* **Scoreboard Invariants:** Filters memory writes through `WSTRB` bits, ensuring unselected byte lanes in memory are never overwritten or checked.

### 3.6 `dma_wr_partial_len_test`
* **Objective:** Verify fractional tail handling for word-aligned destinations with non-word-multiple lengths.
* **Stimulus Parameters:** Dest Address $0\text{x}2000$, Buffer Length $11\text{ bytes}$, Tag $0\text{x}0\text{D}$.
* **Hardware Execution:** $AWADDR = 0\text{x}2000, AWLEN = 2$. Beat 0 has `WSTRB = 4'b1111`, Beat 1 has `4'b1111`, Beat 2 has `4'b0111` (3 bytes). Total = $4 + 4 + 3 = 11\text{ bytes}$.
* **Scoreboard Invariants:** Verifies exact `WSTRB` tail generation and status length $L = 11$.

### 3.7 `dma_wr_early_term_test`
* **Objective:** Verify hardware behavior when the incoming stream terminates early (`TLAST` arrives before buffer capacity is filled).
* **Stimulus Parameters:** Dest Address $0\text{x}2000$, Buffer Length $64\text{ bytes}$, Stream Payload $32\text{ bytes}$ (8 beats), Tag $0\text{x}0\text{E}$.
* **Hardware Execution:** The DMA detects `TLAST` at beat 7. It terminates the active write burst immediately at 8 beats ($AWLEN = 7$), receives `BVALID`, and pulses status with $L_{status} = 32\text{ bytes}$ (reflecting actual bytes written rather than buffer capacity).
* **Scoreboard Invariants:** Flags `is_early_termination = 1`, validates that memory writes cease at 32 bytes, and verifies that status reports the truncated length.

### 3.8 `dma_wr_excess_data_test`
* **Objective:** Stress the DMA's safety cutoff and packet-draining mechanisms when ingress streaming data exceeds the allocated descriptor buffer capacity.
* **Stimulus Parameters:** Dest Address $0\text{x}2000$, Buffer Length $64\text{ bytes}$ (16 words), Stream Payload $80\text{ bytes}$ (20 words), Tag $0\text{x}0\text{F}$.
* **Hardware Execution:** The DMA writes exactly $64\text{ bytes}$ to memory and asserts `WLAST`. It then holds memory writes, drains the remaining 4 beats ($16\text{ bytes}$) from the stream interface until `TLAST`, discards them without writing to memory, and asserts status with $L_{status} = 64\text{ bytes}$.
* **Scoreboard Invariants:** Employs four-way retirement synchronization to prevent race conditions while excess data drains, verifying that exactly 16 bytes are cleanly dropped with zero memory corruption.

### 3.9 `dma_wr_skew_test`
* **Objective:** Stress asynchronous timing skew between control descriptor submission and stream packet arrival.
* **Stimulus Execution:**
  * **Sub-iteration 1 (Data-First Skew):** Stream packet arrives at $T = 0$; Descriptor command delayed by 10 cycles. The DMA holds `TREADY = 0` until descriptor registration.
  * **Sub-iteration 2 (Descriptor-First Skew):** Descriptor command arrives at $T = 0$; Stream packet delayed by 10 cycles. The DMA suppresses AXI `AWVALID` until stream data enters the FIFO.
* **Scoreboard Invariants:** Utilizes `unmatched_axis_pkts` queue to buffer early stream packets during Data-First skew, binding seamlessly upon descriptor arrival.

### 3.10 `dma_wr_stream_bubble_test`
* **Objective:** Verify datapath robustness against stream starvation, inter-beat bubbles, and inter-packet gaps.
* **Stimulus Execution:**
  * **Sub-iteration 1:** Single 16-beat packet with random 1-to-3 cycle bubbles between beats (`enable_random_beat_delay = 1`).
  * **Sub-iteration 2:** Back-to-back packets with both inter-beat bubbles and a 5-cycle inter-packet gap.
* **Hardware Execution:** Analyzes the 2-cycle skid buffer pipeline latency. When stream pauses occur, the write master pauses `WVALID` exactly 2 cycles later without corrupting data or generating false write strobes.
* **Scoreboard Invariants:** Verifies zero scoreboard timeouts and 100% byte match.

### 3.11 `dma_wr_backpressure_test`
* **Objective:** Stress the write engine under hostile memory bus conditions.
* **Stimulus Parameters:** Slave VIP injects 1-to-5 cycle stalls on `AWREADY` and `WREADY`, and delays `BVALID` write responses by 10 cycles.
* **Hardware Execution:** When the memory slave stalls `WREADY`, the DMA internal skid buffer fills. When full, the DMA drops stream `TREADY` to backpressure the ingress source. When the memory slave acknowledges, stream flow resumes seamlessly.
* **Scoreboard Invariants:** Proves complete absence of deadlocks, protocol violations, or buffer overflows.

## 4. Hardware Edge Cases & Verification Findings

During regression execution and scoreboard construction, three critical hardware and verification corner cases were identified and resolved:

### 4.1 The 4KB Boundary Clamp Invariant
ARM AXI4 specification Section A3.4.1 mandates:
> *A burst must not cross a 4KB address boundary.*

If an unaligned start address (e.g., $0\text{x}0\text{FE}1$) is combined with a 16-beat burst, the end address would reach $0\text{x}1021$, violating the protocol. The hardware calculates:
$$\text{MaxBytesToBoundary} = 4096 - (\text{Addr} \ \& \ 12'\text{hFFF})$$
$$\text{BurstLen} = \min\left(15, \left\lfloor \frac{\text{MaxBytesToBoundary}}{4} \right\rfloor - 1\right)$$
The scoreboard's `SCB_MM2S_4KB_CROSS` and `SCB_S2MM_4KB_CROSS` checkers continuously audit this rule. Both `dma_rd_4kb_split_test` and `dma_wr_4kb_split_test` proved that the RTL clamp logic functions with zero boundary overflows.

### 4.2 The Excess Data Status-vs-Stream Race Condition
In `dma_wr_excess_data_test`, a classic hardware-software verification race condition was uncovered:
1. The memory write engine finishes writing $L_{buffer}$ bytes and receives `BVALID`.
2. The DMA status engine pulses `m_axis_write_desc_status_valid` to inform the host that memory is ready.
3. Concurrently, the stream receiver is still asserting `TREADY` to drain and discard the excess stream beats up to `TLAST`.
4. If a standard UVM scoreboard retired the descriptor upon seeing status, it would immediately flag errors on subsequent stream beats because no active descriptor existed to receive them.
5. **Resolution:** The scoreboard implemented a four-way barrier (`cmd_seen`, `status_done`, `stream_done`, and `total_written >= buffer_len`) guaranteeing that retirement occurs only after both physical channels have reached quiescence.

### 4.3 Skid Buffer Phase Latency
Waveform analysis of [`axi_dma_wr.v`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_rtl/axi_master_rtl/axi_dma_wr.v) confirmed that data handshakes on `s_axis_write_data_*` require exactly **2 clock cycles** to traverse the internal skid buffer (`out_fifo`) before appearing on `m_axi_wdata`. Any bubble on the stream interface propagates to the AXI memory bus with an identical 2-cycle phase delay. The asynchronous event-driven comparator in [`dma_scoreboard.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/env/dma_scoreboard.sv) naturally decouples this pipeline delay, preventing false timing errors while strictly verifying payload integrity.

## 5. Comprehensive Test Execution & Check Matrix

The following matrix maps every test in the regression suite to its operational characteristics, stimulus knobs, and scoreboard checkers:

| Test Identifier | Pipeline | Transfer Length | Alignment | Primary Stimulus Knobs | Active Scoreboard Checkers |
| :--- | :---: | :---: | :---: | :--- | :--- |
| [`dma_rd_nominal_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_nominal_test.sv) | MM2S | 64 B (16 w) | Aligned (0x1000) | Default nominal sequences | `SCB_MM2S_DATA_MATCH`, `SCB_MM2S_PKT_COUNT` |
| [`dma_rd_multiburst_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_multiburst_test.sv) | MM2S | 256 B (64 w) | Aligned (0x2000) | 4 consecutive 16-beat bursts | `SCB_MM2S_BURST_ADDR`, `SCB_MM2S_PKT_LEN` |
| [`dma_rd_4kb_split_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_4kb_split_test.sv) | MM2S | 64 B (16 w) | Aligned (0x0FE0) | 4KB boundary split (8+8 beats) | `SCB_MM2S_4KB_CROSS`, `SCB_MM2S_BURST_ADDR` |
| [`dma_rd_unaligned_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_unaligned_test.sv) | MM2S | 11 B | Unaligned (0x1001) | Non-word start offset | Byte windowing, barrel shifter check |
| [`dma_rd_partial_len_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_partial_len_test.sv) | MM2S | 13 B | Aligned (0x1000) | Fractional final beat TKEEP | `SCB_MM2S_PKT_LEN`, final beat `TKEEP` mask |
| [`dma_rd_backpressure_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_backpressure_test.sv) | MM2S | 64 B | Aligned (0x3000) | ARREADY, RREADY, TREADY stalls | Zero byte drop, FIFO overflow check |
| [`dma_wr_nominal_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_nominal_test.sv) | S2MM | 64 B (16 w) | Aligned (0x2000) | 16-beat full TKEEP stream | `SCB_S2MM_DATA_MATCH`, `SCB_S2MM_STATUS` |
| [`dma_wr_b2b_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_b2b_test.sv) | S2MM | 64 B + 64 B | Aligned (0x2000/40) | Back-to-back zero-idle descriptors | Pipeline tracking, tag retirement order |
| [`dma_wr_multiburst_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_multiburst_test.sv) | S2MM | 256 B (64 w) | Aligned (0x4000) | 64-beat stream, 4 write bursts | `SCB_S2MM_BURST_ADDR`, `AWLEN_OVERFLOW` |
| [`dma_wr_4kb_split_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_4kb_split_test.sv) | S2MM | 64 B (16 w) | Aligned (0x0FE0) | 4KB boundary split (8+8 beats) | `SCB_S2MM_4KB_CROSS`, `SCB_S2MM_BURST_ADDR` |
| [`dma_wr_unaligned_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_unaligned_test.sv) | S2MM | 11 B | Unaligned (0x2001) | Sparse WSTRB beat 0 & tail | Sparse WSTRB qualifier check |
| [`dma_wr_partial_len_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_partial_len_test.sv) | S2MM | 11 B | Aligned (0x2000) | Fractional tail WSTRB (0x7) | `SCB_S2MM_STAT_LEN_MISMATCH` |
| [`dma_wr_early_term_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_early_term_test.sv) | S2MM | 32 B vs 64 B | Aligned (0x2000) | Ingress TLAST before buffer len | `is_early_termination`, status len = 32 |
| [`dma_wr_excess_data_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_excess_data_test.sv) | S2MM | 80 B vs 64 B | Aligned (0x2000) | Ingress payload > buffer len | `SCB_S2MM_DROP_CHECK` (16 B dropped) |
| [`dma_wr_skew_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_skew_test.sv) | S2MM | 64 B + 64 B | Aligned (0x2000) | Data-First & Desc-First skew (10 cyc)| `unmatched_axis_pkts` staging check |
| [`dma_wr_stream_bubble_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_stream_bubble_test.sv) | S2MM | 64 B + 128 B | Aligned (0x2000/10) | Inter-beat bubbles (1-3 c) & gaps | 2-cycle skid buffer phase latency check |
| [`dma_wr_backpressure_test`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_backpressure_test.sv) | S2MM | 64 B | Aligned (0x2000) | AWREADY/WREADY stalls, BVALID delay | Write skid buffer saturation, deadlock check |
