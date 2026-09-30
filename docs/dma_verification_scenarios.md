# DMA Verification Scenarios Catalog

**Project:** AXI4 DMA Subsystem UVM Verification  
**Author:** Akshansh Chaurasia  
**Supervisor:** Dr. Rakesh Palisetty  
**Institution:** Shiv Nadar University  

---

## Format Definition (Excel Sheet Mapping)

Every verification scenario is defined by four core fields:
1. **Scenario Title (ID):** Name and identifier of the scenario.
2. **Verification Intent:** What design feature, boundary, or failure mode is being verified.
3. **Stimulus Configuration:** Inputs provided to the Descriptor, Memory Responder, and Stream interfaces.
4. **Scoreboard Checking Logic:** Exact rules the scoreboard uses to evaluate correctness.

---

# Feature 2: MM2S (Memory-Mapped to Stream Read Engine)

### Scenario 1.1: Nominal Aligned Single-Burst Read
* **Scenario ID:** `MM2S_SCEN_01`
* **Verification Intent:** Verify baseline single-burst read operation (1 to 16 beats) with word-aligned start address and full byte enables.
* **Stimulus Configuration:**
  - Read Descriptor: `start_addr = 0x1000` (aligned), `xfer_len = 64 bytes` (16 beats), `tag = 8'h01`.
  - AXI Memory Slave: Pre-loaded with 16 known 32-bit words at `0x1000`; returns `RRESP = OKAY` and `RLAST` on beat 16.
  - Stream Read VIP: Ready continuously (`TREADY = 1`).
* **Scoreboard Checking Logic:**
  - Check that all 16 stream beats match memory read beats: `stream_data[i] == mem_rdata[i]`.
  - Check that `TKEEP == 4'b1111` for all 16 beats.
  - Check that `TLAST == 1` only on beat 15 (0-indexed).
  - Check that completion status pulses with `tag == 8'h01` and `error == 4'd0`.

---

### Scenario 1.2: Multi-Burst Slicing Read (>16 Beats)
* **Scenario ID:** `MM2S_SCEN_02`
* **Verification Intent:** Verify that transfers larger than `AXI_MAX_BURST_LEN` (64 bytes) are automatically sliced into consecutive 16-beat AXI bursts with incremental address calculation and seamless stream assembly.
* **Stimulus Configuration:**
  - Read Descriptor: `start_addr = 0x1000`, `xfer_len = 256 bytes` (64 beats = 4 bursts of 16 beats), `tag = 8'h02`.
  - AXI Memory Slave: Pre-loaded with 64 words spanning `0x1000` to `0x10FF`; serves 4 consecutive bursts (`ARLEN = 15`) with `RLAST` on every 16th beat.
  - Stream Read VIP: Ready continuously (`TREADY = 1`).
* **Scoreboard Checking Logic:**
  - Check that DUT generates 4 distinct AR bursts with addresses: `0x1000`, `0x1040`, `0x1080`, `0x10C0` (each with `ARLEN = 15`).
  - Check that all 64 output stream beats match memory data in exact order.
  - Check that intermediate `RLAST` pulses from memory do NOT trigger stream `TLAST`.
  - Check that stream `TLAST == 1` is asserted ONLY on the 64th beat.
  - Check that completion status pulses only after the 64th stream beat with `tag == 8'h02` and `error == 0`.

---

### Scenario 1.3: 4KB Page Boundary Crossing Read
* **Scenario ID:** `MM2S_SCEN_03`
* **Verification Intent:** Verify that when a read transfer crosses a 4KB address boundary (`0x1000`, `0x2000`...), the AR generator clips the burst to terminate exactly at the 4KB edge, preventing AXI protocol violation (A3.4.1).
* **Stimulus Configuration:**
  - Read Descriptor: `start_addr = 0x0FE0` (32 bytes before 4KB edge), `xfer_len = 64 bytes` (16 beats total, crossing into `0x1000`), `tag = 8'h03`.
  - AXI Memory Slave: Pre-loaded across boundary (`0x0FE0` to `0x101F`); responds to two split bursts.
  - Stream Read VIP: Ready continuously (`TREADY = 1`).
* **Scoreboard Checking Logic:**
  - Check that DUT splits the transfer into two separate bursts:
    - Burst 1: `ARADDR = 0x0FE0`, `ARLEN = 7` (8 beats = 32 bytes, ending at `0x0FFF`).
    - Burst 2: `ARADDR = 0x1000`, `ARLEN = 7` (8 beats = 32 bytes, starting at `0x1000`).
  - Check that neither burst crosses `0x1000`.
  - Check that all 16 stream beats are concatenated smoothly without gaps.
  - Check that stream `TLAST == 1` occurs only on beat 15, and status pulses with `tag == 8'h03`.

---

### Scenario 1.4: Unaligned Byte Address Read (Barrel Shifter Verification)
* **Scenario ID:** `MM2S_SCEN_04`
* **Verification Intent:** Verify that unaligned byte start addresses (`offset = +1, +2, +3` bytes) correctly activate the internal barrel shifter datapath and bubble cycle, aligning the requested bytes to byte lane 0 of the stream.
* **Stimulus Configuration:**
  - Read Descriptor: Run 3 sub-iterations:
    - Sub-iter A: `start_addr = 0x1001` (Offset +1 byte), `xfer_len = 16 bytes`, `tag = 8'h04`.
    - Sub-iter B: `start_addr = 0x1002` (Offset +2 bytes), `xfer_len = 16 bytes`, `tag = 8'h05`.
    - Sub-iter C: `start_addr = 0x1003` (Offset +3 bytes), `xfer_len = 16 bytes`, `tag = 8'h06`.
  - AXI Memory Slave: Returns word-aligned 32-bit data from memory.
  - Stream Read VIP: `TREADY = 1`.
* **Scoreboard Checking Logic:**
  - Reference model reconstructs expected stream bytes by extracting bytes starting at `start_addr`:
    `expected_stream_byte[j] == memory_byte[start_addr + j]`.
  - Check that the first stream beat contains requested byte `start_addr` in byte lane 0 (`TDATA[7:0]`).
  - Check that the bubble cycle correctly suppresses invalid data on the first clock.
  - Check that total transferred stream bytes match `xfer_len`.

---

### Scenario 1.5: Partial Final Beat Formatting (TKEEP Masking)
* **Scenario ID:** `MM2S_SCEN_05`
* **Verification Intent:** Verify that transfers ending on non-word boundaries (lengths not divisible by 4) assert the correct partial `TKEEP` byte mask on the final beat alongside `TLAST`.
* **Stimulus Configuration:**
  - Read Descriptor: Run 3 sub-iterations with non-multiple-of-4 lengths:
    - Sub-iter A: `xfer_len = 13 bytes` (3 full beats + 1 byte remainder), `tag = 8'h07`.
    - Sub-iter B: `xfer_len = 14 bytes` (3 full beats + 2 bytes remainder), `tag = 8'h08`.
    - Sub-iter C: `xfer_len = 15 bytes` (3 full beats + 3 bytes remainder), `tag = 8'h09`.
  - AXI Memory Slave: Normal responder.
  - Stream Read VIP: `TREADY = 1`.
* **Scoreboard Checking Logic:**
  - Check that beats 0 to 2 have `TKEEP == 4'b1111` and `TLAST == 0`.
  - Check final beat (beat 3) qualifiers:
    - For 13 bytes: `TKEEP == 4'b0001` and `TLAST == 1`.
    - For 14 bytes: `TKEEP == 4'b0011` and `TLAST == 1`.
    - For 15 bytes: `TKEEP == 4'b0111` and `TLAST == 1`.
  - Check that status reports `error == 4'd0`.

---

### Scenario 1.6: Downstream Stream Backpressure Stalls
* **Scenario ID:** `MM2S_SCEN_06`
* **Verification Intent:** Verify that when the stream receiver asserts backpressure (`TREADY = 0`), the 32-entry output skid FIFO absorbs in-flight beats, halts memory reading when half-full (`m_axi_rready = 0`), and resumes without dropping or duplicating data.
* **Stimulus Configuration:**
  - Read Descriptor: `start_addr = 0x1000`, `xfer_len = 128 bytes` (32 beats), `tag = 8'h0A`.
  - Stream Read VIP: Injects periodic `TREADY = 0` throttle delays (e.g. ready low for 5–10 cycles every 4 beats).
  - AXI Memory Slave: Fast responder (zero memory latency).
* **Scoreboard Checking Logic:**
  - Verify that when output FIFO reaches 16 entries (half-full), DUT deasserts `m_axi_rready`.
  - Check that zero data beats are dropped, duplicated, or reordered during stalls.
  - Check that all 32 beats eventually exit on stream with intact data and valid `TLAST` on beat 31.

---

### Scenario 1.7: Bus Error Propagation (SLVERR & DECERR)
* **Scenario ID:** `MM2S_SCEN_07`
* **Verification Intent:** Verify that when the memory slave returns read response errors (`RRESP = SLVERR` or `DECERR`), the error is latched by `rresp_reg` and reported accurately on the descriptor completion status pulse without locking up the engine.
* **Stimulus Configuration:**
  - Sub-iter A (SLVERR):
    - Read Descriptor: `start_addr = 0x2000`, `xfer_len = 64 bytes`, `tag = 8'h0B`.
    - AXI Memory Slave: Injects `RRESP = 2'b10` (SLVERR) on beat 8 of the burst.
  - Sub-iter B (DECERR):
    - Read Descriptor: `start_addr = 0x3000`, `xfer_len = 64 bytes`, `tag = 8'h0C`.
    - AXI Memory Slave: Injects `RRESP = 2'b11` (DECERR) on beat 4 of the burst.
* **Scoreboard Checking Logic:**
  - For Sub-iter A: Check that completion status pulses with `tag == 8'h0B` and `error == 4'd4` (`DMA_ERROR_AXI_RD_SLVERR`).
  - For Sub-iter B: Check that completion status pulses with `tag == 8'h0C` and `error == 4'd5` (`DMA_ERROR_AXI_RD_DECERR`).
  - Check that `axi_state` and `axis_state` return cleanly to `IDLE` ready for the next descriptor.

---
