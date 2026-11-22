# AXI4 DMA Subsystem: Verification Test Suite & DUT Feature Coverage

## 1. Executive Test Suite Overview

The AMBA AXI4 DMA Subsystem features a dual-engine architecture comprising an MM2S (Memory-to-Stream) Read Controller and an S2MM (Stream-to-Memory) Write Controller. To achieve exhaustive functional verification, the test suite executes 17 dedicated feature tests across both pipelines.

Each test case targets a specific hardware feature, microarchitectural mechanism, or protocol corner case within the synthesizable RTL cores ([`axi_dma_rd.v`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_rtl/axi_master_rtl/axi_dma_rd.v) and [`axi_dma_wr.v`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_rtl/axi_master_rtl/axi_dma_wr.v)).

The preliminary smoke test ([`dma_sanity_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_sanity_test.sv)) is strictly preserved as a post-compile environment sanity check and is excluded from feature regression suites and coverage merge databases.

## 2. MM2S Read Pipeline Feature Verification (6 Tests)

The MM2S Read Controller fetches data from memory-mapped addresses over the AXI4 Read Address (AR) and Read Data (R) channels and packages the data into continuous packets over the AXI4-Stream master interface.

### 2.1 `dma_rd_nominal_test`
* **Source File:** [`dma_rd_nominal_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_nominal_test.sv)
* **Targeted DUT Hardware Feature:**
  * Baseline MM2S Read Master state machine (`STATE_IDLE` -> `STATE_START` -> `STATE_READ`).
  * 32-bit aligned memory fetching through the AXI4 AR and R channels.
  * Internal read data FIFO buffering and egress stream framing.
* **Verification Intent:** Validate that a single-burst, word-aligned transfer completes cleanly with 1-to-1 packet boundary framing, correct payload serialization, and synchronous status reporting.
* **Stimulus Configuration:**
  * Start Address: `0x1000` (Word-aligned: `addr[1:0] = 2'b00`).
  * Transfer Length: `64 bytes` (16 words, single 16-beat burst).
  * Transfer Tag: `0x01`.
* **Hardware Execution Details:**
  * Upon descriptor handshake (`s_axis_read_desc_valid && s_axis_read_desc_ready`), the read engine registers transfer parameters.
  * The AXI read master issues a single burst with `ARADDR = 0x1000` and `ARLEN = 15` (16 beats).
  * Read data words from memory pass through the internal read FIFO and serialize onto `m_axis_read_data_*`.
  * `TLAST` asserts strictly on the 16th beat (byte 63), accompanied by full byte qualifiers `TKEEP = 4'b1111`.
  * Status completes with `m_axis_read_desc_status_valid = 1`, `status_tag = 0x01`, and `status_error = 0`.
* **Scoreboard Checkers & Invariants:**
  * `SCB_MM2S_DATA_MATCH`: 100% pairwise match between memory read data and stream bytes.
  * `SCB_MM2S_PKT_COUNT`: Exactly 1 stream packet observed.
  * `SCB_MM2S_PKT_LEN`: Stream packet length equals requested 64 bytes.

### 2.2 `dma_rd_multiburst_test`
* **Source File:** [`dma_rd_multiburst_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_multiburst_test.sv)
* **Targeted DUT Hardware Feature:**
  * Multi-burst address decomposition logic in [`axi_dma_rd.v`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_rtl/axi_master_rtl/axi_dma_rd.v).
  * Automatic 16-beat burst length chunking for long transfer lengths exceeding the single-burst limit.
  * Internal address accumulator (`op_addr`) incrementation across successive bursts.
  * Seamless stream merging across burst boundaries with deferred `TLAST` generation.
* **Verification Intent:** Verify that large transfers are automatically fragmented into consecutive 16-beat AXI read bursts without address discontinuities or premature stream termination.
* **Stimulus Configuration:**
  * Start Address: `0x2000` (Word-aligned).
  * Transfer Length: `256 bytes` (64 words, requiring four 16-beat bursts).
  * Transfer Tag: `0x02`.
* **Hardware Execution Details:**
  * The DMA splits the 256-byte transfer into 4 consecutive AXI read bursts:
    * Burst 1: `ARADDR = 0x2000`, `ARLEN = 15` (Bytes 0 to 63)
    * Burst 2: `ARADDR = 0x2040`, `ARLEN = 15` (Bytes 64 to 127)
    * Burst 3: `ARADDR = 0x2080`, `ARLEN = 15` (Bytes 128 to 191)
    * Burst 4: `ARADDR = 0x20C0`, `ARLEN = 15` (Bytes 192 to 255)
  * Data words from all 4 bursts stream continuously through the read FIFO.
  * `TLAST` is held low across Bursts 1, 2, and 3, and asserts strictly on the 64th beat of the combined stream.
* **Scoreboard Checkers & Invariants:**
  * `SCB_MM2S_BURST_ADDR`: Sequential address progression `ARADDR[k+1] == ARADDR[k] + ((ARLEN[k]+1) * 4)`.
  * `SCB_MM2S_PKT_COUNT`: Exactly 1 continuous stream packet produced for all 4 bursts.
  * `SCB_MM2S_PKT_LEN`: Total packet length equals 256 bytes.

### 2.3 `dma_rd_4kb_split_test`
* **Source File:** [`dma_rd_4kb_split_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_4kb_split_test.sv)
* **Targeted DUT Hardware Feature:**
  * 4KB page boundary calculation logic in [`axi_dma_rd.v`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_rtl/axi_master_rtl/axi_dma_rd.v).
  * Hardware burst clamping logic enforcing ARM AMBA AXI4 Section A3.4.1 (no burst may cross a 4KB boundary).
  * Dynamic burst splitting into pre-boundary and post-boundary read operations.
* **Verification Intent:** Prove that when a memory read spans across a 4KB address boundary, the hardware clamps the first burst to end at the boundary and initiates a new burst at the boundary base.
* **Stimulus Configuration:**
  * Start Address: `0x0FE0` (32 bytes before the 4KB boundary at `0x1000`).
  * Transfer Length: `64 bytes` (16 words; 32 bytes pre-boundary + 32 bytes post-boundary).
  * Transfer Tag: `0x03`.
* **Hardware Execution Details:**
  * The DMA calculates remaining bytes to the boundary: `4096 - (0x0FE0 & 0xFFF) = 32 bytes` (8 words).
  * The DMA clamps Burst 1 to 8 beats: `ARADDR = 0x0FE0`, `ARLEN = 7` (Spans `0x0FE0` to `0x0FFF`).
  * The DMA automatically issues Burst 2 for the remaining 8 beats: `ARADDR = 0x1000`, `ARLEN = 7` (Spans `0x1000` to `0x101F`).
  * Neither burst crosses `0x1000`. The two bursts merge transparently into one 64-byte stream packet.
* **Scoreboard Checkers & Invariants:**
  * `SCB_MM2S_4KB_CROSS`: Formal assertion checking `(ARADDR & 12'hFFF) + ((ARLEN + 1) * 4) <= 4096`.
  * `SCB_MM2S_BURST_ADDR`: Confirms Burst 2 begins exactly at `0x1000`.

### 2.4 `dma_rd_unaligned_test`
* **Source File:** [`dma_rd_unaligned_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_unaligned_test.sv)
* **Targeted DUT Hardware Feature:**
  * Unaligned address handling logic (`ENABLE_UNALIGNED = 1`).
  * Internal multi-stage barrel shifter in [`axi_dma_rd.v`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_rtl/axi_master_rtl/axi_dma_rd.v).
  * Byte-shifting logic aligning unaligned memory data words onto byte lane 0 of the streaming interface.
  * Discard logic for prefix bytes in beat 0.
* **Verification Intent:** Verify that reading from a non-word-aligned memory address causes the DMA to fetch aligned words, shift them through the internal barrel shifter, discard unused prefix bytes, and output a packed, continuous byte stream.
* **Stimulus Configuration:**
  * Start Address: `0x1001` (Offset 1: byte-unaligned, `addr[1:0] = 2'b01`).
  * Transfer Length: `11 bytes` (spans `0x1001` to `0x100B`).
  * Transfer Tag: `0x04`.
* **Hardware Execution Details:**
  * The DMA rounds down the start address to issue an aligned memory read: `ARADDR = 0x1000`, `ARLEN = 2` (3 words, 12 bytes fetched).
  * Word 0 contains bytes at `0x1000`, `0x1001`, `0x1002`, `0x1003`.
  * The barrel shifter shifts the data right by 1 byte, discarding byte `0x1000` and presenting byte `0x1001` on lane 0.
  * The remaining bytes are packed contiguously into stream beats with `TLAST` asserted on byte `0x100B`.
* **Scoreboard Checkers & Invariants:**
  * Windowing comparison ensures memory byte `0x1000` is discarded and only bytes `[0x1001 : 0x100B]` appear on AXIS.
  * `SCB_MM2S_PKT_LEN`: Stream length strictly equals 11 bytes.

### 2.5 `dma_rd_partial_len_test`
* **Source File:** [`dma_rd_partial_len_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_partial_len_test.sv)
* **Targeted DUT Hardware Feature:**
  * Fractional length truncation logic in the MM2S egress datapath.
  * Stream byte qualifier (`TKEEP`) mask generation on the final transfer beat.
  * Synchronous `TLAST` assertion on partial words.
* **Verification Intent:** Verify that when the requested transfer length is not an integer multiple of 4 bytes, the final stream beat asserts partial `TKEEP` qualifiers matching the remaining byte count.
* **Stimulus Configuration:**
  * Start Address: `0x1000` (Word-aligned).
  * Transfer Length: `13 bytes` (3 full words + 1 fractional byte).
  * Transfer Tag: `0x05`.
* **Hardware Execution Details:**
  * The DMA issues an AXI read burst for 4 words (`ARADDR = 0x1000`, `ARLEN = 3`).
  * Beats 0, 1, and 2 serialize onto AXIS with full `TKEEP = 4'b1111` (12 bytes).
  * Beat 3 serializes the 13th byte on lane 0 with partial `TKEEP = 4'b0001` and `TLAST = 1`.
* **Scoreboard Checkers & Invariants:**
  * Exact final beat `TKEEP` mask audit (`4'b0001`).
  * `SCB_MM2S_PKT_LEN`: Verifies total bytes checked equals 13.

### 2.6 `dma_rd_backpressure_test`
* **Source File:** [`dma_rd_backpressure_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_backpressure_test.sv)
* **Targeted DUT Hardware Feature:**
  * Elastic flow control and backpressure absorption in the read datapath.
  * Internal read FIFO full/empty watermark tracking.
  * Simultaneous handling of memory-side stalls (`ARREADY=0`, `RREADY` deassertion) and stream-side stalls (`TREADY=0`).
* **Verification Intent:** Prove that the read engine operates losslessly under heavy bus and stream backpressure without data corruption, FIFO overflow, or protocol deadlocks.
* **Stimulus Configuration:**
  * Start Address: `0x3000`, Length: `64 bytes`, Tag: `0x06`.
  * Memory Slave VIP: Random 1-to-5 cycle stalls on `ARREADY` and delayed `RVALID`.
  * Stream Consumer VIP: Random 1-to-5 cycle stalls on `TREADY`.
* **Hardware Execution Details:**
  * When the stream consumer drops `TREADY`, data backs up into the DMA's internal read FIFO.
  * When the FIFO reaches its almost-full threshold, the DMA deasserts `m_axi_rready` to pause incoming memory data beats.
  * Once `TREADY` reasserts, the FIFO drains and `m_axi_rready` resumes.
* **Scoreboard Checkers & Invariants:**
  * `SCB_MM2S_DATA_MATCH`: 100% byte integrity verified across all backpressure cycles.
  * Zero dropped bytes, zero duplicate beats, clean status retirement.

## 3. S2MM Write Pipeline Feature Verification (11 Tests)

The S2MM Write Controller captures streaming packets from `s_axis_write_data_*` and commits them to memory-mapped buffers via AXI4 AW, W, and B channels.

### 3.1 `dma_wr_nominal_test`
* **Source File:** [`dma_wr_nominal_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_nominal_test.sv)
* **Targeted DUT Hardware Feature:**
  * Baseline S2MM Write Master state machine (`STATE_IDLE` -> `STATE_START` -> `STATE_WRITE`).
  * Ingress stream reception, internal write FIFO buffering, and AXI4 AW/W burst generation.
  * Full write strobe (`WSTRB = 4'b1111`) generation.
  * AXI write response channel (`BVALID/BREADY`) handshaking and descriptor status pulse generation.
* **Verification Intent:** Establish baseline stream-to-memory write operation for word-aligned, full-packet transfers.
* **Stimulus Configuration:**
  * Destination Address: `0x2000` (Word-aligned).
  * Buffer Length: `64 bytes` (16 beats).
  * Stream Payload: `64 bytes` (16 beats, full `TKEEP = 4'b1111`).
  * Transfer Tag: `0x07`.
* **Hardware Execution Details:**
  * 16 beats of streaming data enter the internal write FIFO.
  * The DMA issues `AWADDR = 0x2000`, `AWLEN = 15`.
  * The DMA drives 16 write data beats on `m_axi_wdata` with `WSTRB = 4'b1111` and `WLAST` on beat 15.
  * Upon receiving `BVALID` with `BRESP = OKAY`, the DMA pulses status: `status_tag = 0x07`, `status_len = 64`, `status_error = 0`.
* **Scoreboard Checkers & Invariants:**
  * `SCB_S2MM_DATA_MATCH`: Pairwise lockstep comparison of stream payload against memory write data.
  * `SCB_S2MM_STATUS`: Validates reported status length equals 64 bytes.

### 3.2 `dma_wr_b2b_test`
* **Source File:** [`dma_wr_b2b_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_b2b_test.sv)
* **Targeted DUT Hardware Feature:**
  * Descriptor queueing logic and pipelined state transitions.
  * Back-to-back transfer execution with zero idle cycles between descriptor completions.
  * Tag tracking across back-to-back transfers.
* **Verification Intent:** Verify that multiple descriptors execute in succession without state machine deadlocks or inter-descriptor bubbles.
* **Stimulus Configuration:**
  * Descriptor 1: Dest `0x2000`, Length `64 bytes`, Tag `0x08`.
  * Descriptor 2: Dest `0x2040`, Length `64 bytes`, Tag `0x09`.
  * Stream Ingress: Two back-to-back 16-beat packets with zero inter-packet gap.
* **Hardware Execution Details:**
  * Descriptor 2 is enqueued while Descriptor 1 is in-flight.
  * Immediately upon receiving `BVALID` for Descriptor 1, the DMA pulses status for Tag `0x08` and initiates Descriptor 2 without returning to idle.
* **Scoreboard Checkers & Invariants:**
  * FIFO queue tracking in `s2mm_queue` confirms strict in-order execution.
  * Both tags `0x08` and `0x09` retire with 100% byte accuracy.

### 3.3 `dma_wr_multiburst_test`
* **Source File:** [`dma_wr_multiburst_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_multiburst_test.sv)
* **Targeted DUT Hardware Feature:**
  * Multi-burst write segmentation in [`axi_dma_wr.v`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_rtl/axi_master_rtl/axi_dma_wr.v).
  * 16-beat burst length clamping for streaming payloads exceeding 64 bytes.
  * Monotonic destination address progression across write bursts.
  * Status pulse gating until the final burst's write response completes.
* **Verification Intent:** Verify that large streaming packets are segmented into legal 16-beat AXI write bursts and that transfer status is generated only after all bursts commit.
* **Stimulus Configuration:**
  * Destination Address: `0x4000`, Buffer Length: `256 bytes`.
  * Stream Payload: `256 bytes` (64 beats).
  * Transfer Tag: `0x0A`.
* **Hardware Execution Details:**
  * The DMA breaks the incoming stream into 4 successive 16-beat write bursts:
    * Burst 1: `AWADDR = 0x4000`, `AWLEN = 15` (64 bytes)
    * Burst 2: `AWADDR = 0x4040`, `AWLEN = 15` (64 bytes)
    * Burst 3: `AWADDR = 0x4080`, `AWLEN = 15` (64 bytes)
    * Burst 4: `AWADDR = 0x40C0`, `AWLEN = 15` (64 bytes)
  * Each burst asserts `WLAST` on its 16th beat and waits for its respective `BVALID`.
  * Status for Tag `0x0A` is asserted only after the 4th `BVALID` arrives.
* **Scoreboard Checkers & Invariants:**
  * `SCB_S2MM_BURST_ADDR`: Sequential address progression `AWADDR[k+1] == AWADDR[k] + ((AWLEN[k]+1) * 4)`.
  * `SCB_S2MM_AWLEN_OVERFLOW`: Confirms no burst exceeds 16 beats.

### 3.4 `dma_wr_4kb_split_test`
* **Source File:** [`dma_wr_4kb_split_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_4kb_split_test.sv)
* **Targeted DUT Hardware Feature:**
  * 4KB boundary write clamp logic in [`axi_dma_wr.v`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_rtl/axi_master_rtl/axi_dma_wr.v).
  * Enforcing ARM AMBA AXI4 Section A3.4.1 for memory writes.
  * Burst fragmentation across the 4KB boundary while maintaining continuous stream consumption.
* **Verification Intent:** Verify that memory write bursts crossing a 4KB page boundary are split without dropping or misaligning stream beats.
* **Stimulus Configuration:**
  * Destination Address: `0x0FE0` (32 bytes before 4KB boundary at `0x1000`).
  * Buffer Length: `64 bytes`, Stream Payload: `64 bytes`.
  * Transfer Tag: `0x0B`.
* **Hardware Execution Details:**
  * The DMA clamps Burst 1 to 8 beats: `AWADDR = 0x0FE0`, `AWLEN = 7` (32 bytes up to `0x0FFF`).
  * The DMA issues Burst 2 for the remaining 8 beats: `AWADDR = 0x1000`, `AWLEN = 7` (32 bytes from `0x1000` to `0x101F`).
  * Neither burst crosses `0x1000`.
* **Scoreboard Checkers & Invariants:**
  * `SCB_S2MM_4KB_CROSS`: Formal check `(AWADDR & 12'hFFF) + ((AWLEN + 1) * 4) <= 4096`.
  * `SCB_S2MM_BURST_ADDR`: Confirms Burst 2 begins exactly at `0x1000`.

### 3.5 `dma_wr_unaligned_test`
* **Source File:** [`dma_wr_unaligned_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_unaligned_test.sv)
* **Targeted DUT Hardware Feature:**
  * Unaligned write address alignment (`ENABLE_UNALIGNED = 1`).
  * Sparse write strobe (`WSTRB`) generation logic in [`axi_dma_wr.v`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_rtl/axi_master_rtl/axi_dma_wr.v).
  * Masking of unaligned prefix byte lanes in beat 0 and suffix lanes in the final beat.
* **Verification Intent:** Verify that writing to a non-word-aligned destination address generates sparse `WSTRB` bits to prevent overwriting adjacent memory locations.
* **Stimulus Configuration:**
  * Destination Address: `0x2001` (Offset 1: `dest_addr[1:0] = 2'b01`).
  * Buffer Length: `11 bytes`, Stream Payload: `11 bytes`.
  * Transfer Tag: `0x0C`.
* **Hardware Execution Details:**
  * The DMA aligns `AWADDR` down to `0x2000` and issues a 3-beat burst (`AWLEN = 2`).
  * Beat 0: `WSTRB = 4'b1110` (Byte lane 0 is masked; lanes 1, 2, 3 receive bytes 0, 1, 2 of stream).
  * Beat 1: `WSTRB = 4'b1111` (All 4 lanes active; bytes 3, 4, 5, 6 written).
  * Beat 2: `WSTRB = 4'b1111` (Bytes 7, 8, 9, 10 written; total 11 bytes committed).
* **Scoreboard Checkers & Invariants:**
  * Qualifies actual written bytes strictly by `WSTRB[lane] == 1`.
  * Proves byte lane 0 of word `0x2000` is unwritten and uncorrupted.

### 3.6 `dma_wr_partial_len_test`
* **Source File:** [`dma_wr_partial_len_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_partial_len_test.sv)
* **Targeted DUT Hardware Feature:**
  * Fractional tail write handling for word-aligned destinations.
  * Synthesis of sparse `WSTRB` on the final write beat for non-word-multiple lengths.
  * Status length calculation for fractional transfers.
* **Verification Intent:** Verify that a transfer with a non-word-multiple length masks unused lanes on the final write beat and reports the exact byte count in status.
* **Stimulus Configuration:**
  * Destination Address: `0x2000` (Word-aligned).
  * Buffer Length: `11 bytes` (2 full words + 3 fractional bytes).
  * Transfer Tag: `0x0D`.
* **Hardware Execution Details:**
  * The DMA issues `AWADDR = 0x2000`, `AWLEN = 2` (3 beats).
  * Beats 0 and 1 assert full `WSTRB = 4'b1111` (8 bytes).
  * Beat 2 asserts sparse `WSTRB = 4'b0111` (3 bytes; lane 3 masked).
  * Status reports `status_len = 11`.
* **Scoreboard Checkers & Invariants:**
  * Sparse `WSTRB` verification on beat 2 (`4'b0111`).
  * `SCB_S2MM_STAT_LEN_MISMATCH`: Asserts reported status length equals 11.

### 3.7 `dma_wr_early_term_test`
* **Source File:** [`dma_wr_early_term_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_early_term_test.sv)
* **Targeted DUT Hardware Feature:**
  * Ingress stream early termination detection (`TLAST` arrives before buffer length is exhausted).
  * Dynamic write burst truncation in [`axi_dma_wr.v`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_rtl/axi_master_rtl/axi_dma_wr.v).
  * Early status generation reporting actual bytes transferred rather than buffer capacity.
* **Verification Intent:** Verify that when the stream source asserts `TLAST` prematurely, the DMA ceases memory writes, commits the truncated burst, and reports the actual transferred byte count.
* **Stimulus Configuration:**
  * Destination Address: `0x2000`, Buffer Length: `64 bytes` (16 beats allocated).
  * Stream Payload: `32 bytes` (8 beats; `TLAST` asserts on beat 7).
  * Transfer Tag: `0x0E`.
* **Hardware Execution Details:**
  * Stream packet terminates at beat 7.
  * The DMA detects early `TLAST`, terminates the in-flight write burst at 8 beats (`AWLEN = 7`), and drives `WLAST` on beat 7.
  * Status completes with `status_len = 32 bytes` (reflecting actual bytes written rather than the 64-byte buffer capacity).
* **Scoreboard Checkers & Invariants:**
  * Flags `is_early_termination = 1`.
  * Verifies that exactly 32 bytes are written to memory and status reports 32 bytes.

### 3.8 `dma_wr_excess_data_test`
* **Source File:** [`dma_wr_excess_data_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_excess_data_test.sv)
* **Targeted DUT Hardware Feature:**
  * Buffer overrun protection and packet draining logic in [`axi_dma_wr.v`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_rtl/axi_master_rtl/axi_dma_wr.v).
  * Hardware write cutoff at programmed buffer boundary.
  * Excess stream beat draining and dropping until `TLAST`.
  * Prevention of memory corruption on buffer overflow.
* **Verification Intent:** Verify that when ingress streaming data exceeds the allocated buffer capacity, the DMA cuts off memory writes at the buffer limit, drains and discards excess stream beats, and completes without memory corruption or hang.
* **Stimulus Configuration:**
  * Destination Address: `0x2000`, Buffer Length: `64 bytes` (16 beats).
  * Stream Payload: `80 bytes` (20 beats; 16 beats buffer + 4 beats excess).
  * Transfer Tag: `0x0F`.
* **Hardware Execution Details:**
  * The DMA writes the first 16 beats (64 bytes) to memory with `WLAST` on beat 15.
  * The memory write channel completes with `BVALID`, and status is pulsed for 64 bytes.
  * The stream interface continues asserting `TREADY` to consume beats 16 to 19 until `TLAST`, dropping all 4 excess beats without writing them to memory.
* **Scoreboard Checkers & Invariants:**
  * `SCB_S2MM_DROP_CHECK`: Verifies that exactly 16 excess stream bytes were discarded without memory corruption.
  * Proves memory beyond `0x203F` is untouched.

### 3.9 `dma_wr_skew_test`
* **Source File:** [`dma_wr_skew_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_skew_test.sv)
* **Targeted DUT Hardware Feature:**
  * Asynchronous control-data timing skew resilience.
  * **Data-First Skew:** Stream arrives before descriptor submission; DUT holds `TREADY = 0` to backpressure unallocated ingress data.
  * **Descriptor-First Skew:** Descriptor arrives before stream data; DUT suppresses AXI `AWVALID` until stream data ingresses without deadlocking.
* **Verification Intent:** Stress both directions of asynchronous arrival skew between software control plane and physical streaming hardware.
* **Stimulus Configuration:**
  * **Sub-iteration 1 (Data-First):** Stream packet arrives at cycle 0; Descriptor delayed by 10 cycles (Tag `0x0E`).
  * **Sub-iteration 2 (Descriptor-First):** Descriptor submitted at cycle 0; Stream packet delayed by 10 cycles (Tag `0x0F`).
* **Hardware Execution Details:**
  * In Sub-iteration 1, the DMA maintains `TREADY = 0` until the descriptor registers destination address and buffer capacity.
  * In Sub-iteration 2, the DMA enters write preparation but delays asserting `m_axi_awvalid` until streaming data enters the write FIFO.
* **Scoreboard Checkers & Invariants:**
  * Scoreboard uses `unmatched_axis_pkts` queue to stage early stream data during Data-First skew, binding seamlessly upon descriptor arrival.
  * Zero deadlocks, zero dropped beats across both skew modes.

### 3.10 `dma_wr_stream_bubble_test`
* **Source File:** [`dma_wr_stream_bubble_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_stream_bubble_test.sv)
* **Targeted DUT Hardware Feature:**
  * Stream starvation resilience and inter-beat bubble tolerance.
  * Internal 2-cycle skid buffer pipeline latency absorption ([`axi_dma_wr.v` lines 916-965](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_rtl/axi_master_rtl/axi_dma_wr.v#L916-L965)).
  * Inter-packet gap handling across multi-packet streaming sequences.
* **Verification Intent:** Verify that streaming pauses (`TVALID = 0` bubbles) propagate through the 2-cycle write skid buffer without corrupting memory write strobes or stalling the pipeline.
* **Stimulus Configuration:**
  * **Sub-iteration 1:** Single 16-beat packet with random 1-to-3 cycle bubbles between beats (Tag `0x10`).
  * **Sub-iteration 2:** Back-to-back packets with inter-beat bubbles and a 5-cycle inter-packet gap (Tags `0x11`, `0x12`).
* **Hardware Execution Details:**
  * Stream beats arrive intermittently. When `TVALID` drops, the DMA holds data in its input registers.
  * The 2-cycle skid buffer phase latency between `s_axis_write_data_*` and `m_axi_wdata` reflects stream bubbles on the AXI bus with exact 2-cycle phase delays.
* **Scoreboard Checkers & Invariants:**
  * Event-driven pair-wise comparator absorbs the 2-cycle pipeline latency.
  * 100% byte match across both sub-iterations with zero false stalls.

### 3.11 `dma_wr_backpressure_test`
* **Source File:** [`dma_wr_backpressure_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_backpressure_test.sv)
* **Targeted DUT Hardware Feature:**
  * Write datapath backpressure propagation and skid buffer saturation.
  * Slave `AWREADY` and `WREADY` stall handling.
  * Delayed `BVALID` write response absorption.
  * Flow control upstream propagation back to stream `TREADY`.
* **Verification Intent:** Prove that heavy memory bus backpressure saturates internal write buffers and propagates upstream to throttle the streaming source without overflow or deadlock.
* **Stimulus Configuration:**
  * Destination Address: `0x2000`, Buffer Length: `64 bytes`, Tag: `0x13`.
  * Memory Slave VIP: Injects random 1-to-5 cycle stalls on `AWREADY` and `WREADY`, and delays `BVALID` by 10 cycles.
* **Hardware Execution Details:**
  * When the memory slave stalls `WREADY`, the DMA internal write skid buffer fills.
  * Once full, the DMA drops `s_axis_write_data_tready` to halt the ingress streaming master.
  * When `WREADY` reasserts, data drains to memory and `TREADY` reasserts.
* **Scoreboard Checkers & Invariants:**
  * Validates zero data loss, zero duplicate writes, and deadlock-free resumption.

## 4. Comprehensive Test Execution & Feature Coverage Matrix

| Test Case File | Pipeline | Transfer Length | Byte Alignment | Targeted DUT Feature | Key Scoreboard Checkers |
| :--- | :---: | :---: | :---: | :--- | :--- |
| [`dma_rd_nominal_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_nominal_test.sv) | MM2S | 64 B | Word-Aligned (`0x1000`) | Baseline read FSM, single burst, stream framing | `SCB_MM2S_DATA_MATCH`, `SCB_MM2S_PKT_COUNT` |
| [`dma_rd_multiburst_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_multiburst_test.sv) | MM2S | 256 B | Word-Aligned (`0x2000`) | Multi-burst decomposition, address accumulator | `SCB_MM2S_BURST_ADDR`, `SCB_MM2S_PKT_LEN` |
| [`dma_rd_4kb_split_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_4kb_split_test.sv) | MM2S | 64 B | Pre-boundary (`0x0FE0`) | 4KB page clamp, pre/post boundary burst split | `SCB_MM2S_4KB_CROSS`, `SCB_MM2S_BURST_ADDR` |
| [`dma_rd_unaligned_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_unaligned_test.sv) | MM2S | 11 B | Unaligned (`0x1001`) | Barrel shifter, prefix byte discard | Address windowing, barrel shifter check |
| [`dma_rd_partial_len_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_partial_len_test.sv) | MM2S | 13 B | Word-Aligned (`0x1000`) | Fractional tail truncation, final beat `TKEEP` | Final beat `TKEEP` mask (`4'b0001`) |
| [`dma_rd_backpressure_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_rd_backpressure_test.sv) | MM2S | 64 B | Word-Aligned (`0x3000`) | Read FIFO flow control, AR/R/TREADY stalls | FIFO watermark check, lossless resumption |
| [`dma_wr_nominal_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_nominal_test.sv) | S2MM | 64 B | Word-Aligned (`0x2000`) | Baseline write FSM, full WSTRB, B response | `SCB_S2MM_DATA_MATCH`, `SCB_S2MM_STATUS` |
| [`dma_wr_b2b_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_b2b_test.sv) | S2MM | 64 B + 64 B | Word-Aligned (`0x2000/40`) | Pipelined descriptor queue, zero-idle transition | `s2mm_queue` FIFO ordering, tag retirement |
| [`dma_wr_multiburst_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_multiburst_test.sv) | S2MM | 256 B | Word-Aligned (`0x4000`) | 16-beat write chunking, address progression | `SCB_S2MM_BURST_ADDR`, `AWLEN_OVERFLOW` |
| [`dma_wr_4kb_split_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_4kb_split_test.sv) | S2MM | 64 B | Pre-boundary (`0x0FE0`) | 4KB boundary write clamp, split AW/W bursts | `SCB_S2MM_4KB_CROSS`, `SCB_S2MM_BURST_ADDR` |
| [`dma_wr_unaligned_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_unaligned_test.sv) | S2MM | 11 B | Unaligned (`0x2001`) | Sparse `WSTRB` generation on beat 0 and tail | Sparse `WSTRB` qualifier check |
| [`dma_wr_partial_len_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_partial_len_test.sv) | S2MM | 11 B | Word-Aligned (`0x2000`) | Fractional write tail, partial final `WSTRB` | `SCB_S2MM_STAT_LEN_MISMATCH` |
| [`dma_wr_early_term_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_early_term_test.sv) | S2MM | 32 B vs 64 B | Word-Aligned (`0x2000`) | Early `TLAST` detection, dynamic burst cutoff | `is_early_termination`, status len = 32 |
| [`dma_wr_excess_data_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_excess_data_test.sv) | S2MM | 80 B vs 64 B | Word-Aligned (`0x2000`) | Overrun protection, excess stream draining | `SCB_S2MM_DROP_CHECK` (16 B dropped cleanly) |
| [`dma_wr_skew_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_skew_test.sv) | S2MM | 64 B + 64 B | Word-Aligned (`0x2000`) | Asynchronous Data-First & Desc-First skew | `unmatched_axis_pkts` staging check |
| [`dma_wr_stream_bubble_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_stream_bubble_test.sv) | S2MM | 64 B + 128 B | Word-Aligned (`0x2000/10`) | Stream bubble tolerance, 2-cycle skid latency | 2-cycle skid buffer phase latency check |
| [`dma_wr_backpressure_test.sv`](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/uvm/tests/dma_tests/dma_wr_backpressure_test.sv) | S2MM | 64 B | Word-Aligned (`0x2000`) | Write skid buffer saturation, AW/W/B stalls | Upstream `TREADY` throttling, deadlock check |
