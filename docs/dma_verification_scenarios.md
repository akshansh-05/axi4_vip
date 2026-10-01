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

# Feature 1: MM2S (Memory-Mapped to Stream Read Engine)

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

# Feature 2: S2MM (Stream-to-Memory Write Engine)

### Scenario 2.1: Nominal Aligned Single-Burst Write
* **Scenario ID:** `S2MM_SCEN_01`
* **Verification Intent:** Verify baseline single-burst write operation (1 to 16 beats): concurrent descriptor and stream acceptance, generation of legal AW and W bursts, B-channel retirement, and completion status reporting.
* **Stimulus Configuration:**
  - Write Descriptor: `dest_addr = 0x2000` (aligned), `buffer_len = 64 bytes` (16 beats), `tag = 8'h01`.
  - Stream Write VIP: Sends 1 packet of 16 beats (64 bytes), with `TKEEP = 4'b1111` and `TLAST = 1` on beat 15.
  - AXI Memory Slave: Accepts AW and W bursts; returns `BRESP = OKAY` on B channel.
* **Scoreboard Checking Logic:**
  - Check that all 16 memory write beats match ingress stream beats: `axi_wdata[i] == stream_tdata[i]`.
  - Check that `WSTRB == 4'b1111` for all 16 beats.
  - Check that `WLAST == 1` only on beat 15.
  - Check that status pulses with `status_len == 64`, `tag == 8'h01`, and `error == 4'd0`.

---

### Scenario 2.2: Back-to-Back (B2B) Pipelined Descriptor Writes
* **Scenario ID:** `S2MM_SCEN_02`
* **Verification Intent:** Verify descriptor pipelining and Status Tracking FIFO credit management: DMA accepts Descriptor 2 immediately after Descriptor 1 without waiting for B-channel response of Descriptor 1.
* **Stimulus Configuration:**
  - Write Descriptor 1: `dest_addr = 0x2000`, `buffer_len = 64 bytes`, `tag = 8'h01` + Stream Packet 1 (16 beats).
  - Write Descriptor 2 (Back-to-back): `dest_addr = 0x3000`, `buffer_len = 64 bytes`, `tag = 8'h02` + Stream Packet 2 (16 beats).
  - AXI Memory Slave: Inserts a 5-cycle delay before asserting `BVALID` for Burst 1 to force overlap.
* **Scoreboard Checking Logic:**
  - Verify that `status_fifo` stores both burst entries concurrently (`active_count_reg == 2`).
  - Verify that Status 1 reports `tag == 8'h01` and `status_len == 64`.
  - Verify that Status 2 reports `tag == 8'h02` and `status_len == 64`.
  - Verify data integrity for both packets in memory independently without byte crossover.

---

### Scenario 2.3: Multi-Burst Slicing Write (>16 Beats)
* **Scenario ID:** `S2MM_SCEN_03`
* **Verification Intent:** Verify that stream writes larger than `AXI_MAX_BURST_LEN` (64 bytes) are segmented into consecutive 16-beat AXI bursts (`AWLEN = 15`), tracking each burst in `status_fifo` and pulsing status only on final burst retirement.
* **Stimulus Configuration:**
  - Write Descriptor: `dest_addr = 0x2000`, `buffer_len = 256 bytes` (64 beats), `tag = 8'h03`.
  - Stream Write VIP: Sends 1 continuous packet of 64 beats (256 bytes) with `TLAST = 1` on beat 63.
  - AXI Memory Slave: Normal active responder.
* **Scoreboard Checking Logic:**
  - Check that DUT generates 4 distinct AW bursts: `0x2000`, `0x2040`, `0x2080`, `0x20C0` (each with `AWLEN = 15`).
  - Check that each burst asserts `WLAST = 1` on its 16th beat.
  - Check that all 64 stream beats are written to memory in exact order.
  - Check that only 1 completion status pulses at the end with `status_len == 256` and `tag == 8'h03`.

---

### Scenario 2.4: 4KB Page Boundary Crossing on Write
* **Scenario ID:** `S2MM_SCEN_04`
* **Verification Intent:** Verify that when an S2MM write burst crosses a 4KB address boundary (`0x1000`, `0x2000`...), the AW generator clamps the burst at the 4KB edge and splits it into two legal bursts.
* **Stimulus Configuration:**
  - Write Descriptor: `dest_addr = 0x1FE0` (32 bytes before 4KB edge), `buffer_len = 64 bytes` (16 beats), `tag = 8'h04`.
  - Stream Write VIP: Sends 1 packet of 16 beats (64 bytes) with `TLAST = 1` on beat 15.
  - AXI Memory Slave: Normal active responder.
* **Scoreboard Checking Logic:**
  - Check that DUT generates two split write bursts:
    - Burst 1: `AWADDR = 0x1FE0`, `AWLEN = 7` (8 beats = 32 bytes, ending at `0x1FFF`).
    - Burst 2: `AWADDR = 0x2000`, `AWLEN = 7` (8 beats = 32 bytes, starting at `0x2000`).
  - Check that neither burst crosses `0x2000`.
  - Check that all 64 bytes are written to memory across the boundary without corruption.

---

### Scenario 2.5: Unaligned Destination Address & WSTRB Masking
* **Scenario ID:** `S2MM_SCEN_05`
* **Verification Intent:** Verify that unaligned destination start addresses (`offset = +1, +2, +3` bytes) activate the write barrel shifter and mask out unused lower byte lanes on the first write beat via `WSTRB`.
* **Stimulus Configuration:**
  - Write Descriptor: Run 3 sub-iterations:
    - Sub-iter A: `dest_addr = 0x2001` (Offset +1 byte), `buffer_len = 16 bytes`, `tag = 8'h05`.
    - Sub-iter B: `dest_addr = 0x2002` (Offset +2 bytes), `buffer_len = 16 bytes`, `tag = 8'h06`.
    - Sub-iter C: `dest_addr = 0x2003` (Offset +3 bytes), `buffer_len = 16 bytes`, `tag = 8'h07`.
  - Stream Write VIP: Sends matching packets of 16 bytes.
  - AXI Memory Slave: Normal responder.
* **Scoreboard Checking Logic:**
  - Check first beat byte enables on AXI W channel:
    - For offset +1: `WSTRB = 4'b1110` (byte 0 disabled, memory at `0x2000` unmodified).
    - For offset +2: `WSTRB = 4'b1100` (bytes 0, 1 disabled, memory at `0x2000-0x2001` unmodified).
    - For offset +3: `WSTRB = 4'b1000` (bytes 0, 1, 2 disabled, memory at `0x2000-0x2002` unmodified).
  - Check that incoming stream bytes are shifted to align with the active byte lanes.
  - Check that adjacent memory bytes are not corrupted.

---

### Scenario 2.6: Partial Final Beat Formatting (WSTRB Masking)
* **Scenario ID:** `S2MM_SCEN_06`
* **Verification Intent:** Verify that transfers ending on non-word boundaries mask out unused upper byte lanes on the final AXI write beat using `WSTRB`.
* **Stimulus Configuration:**
  - Write Descriptor: Run 3 sub-iterations with non-multiple-of-4 lengths:
    - Sub-iter A: `dest_addr = 0x2000`, `buffer_len = 13 bytes` (3 full beats + 1 byte remainder), `tag = 8'h08`.
    - Sub-iter B: `dest_addr = 0x2000`, `buffer_len = 14 bytes` (3 full beats + 2 bytes remainder), `tag = 8'h09`.
    - Sub-iter C: `dest_addr = 0x2000`, `buffer_len = 15 bytes` (3 full beats + 3 bytes remainder), `tag = 8'h0A`.
  - Stream Write VIP: Sends matching packet lengths.
* **Scoreboard Checking Logic:**
  - Check that beats 0 to 2 have `WSTRB == 4'b1111`.
  - Check final beat (beat 3) `WSTRB` qualifiers:
    - For 13 bytes: `WSTRB == 4'b0001` and `WLAST == 1`.
    - For 14 bytes: `WSTRB == 4'b0011` and `WLAST == 1`.
    - For 15 bytes: `WSTRB == 4'b0111` and `WLAST == 1`.
  - Check that bytes past the transfer end are unmodified in memory.

---

### Scenario 2.7: Early Stream Termination (STATE_FINISH_BURST Recovery)
* **Scenario ID:** `S2MM_SCEN_07`
* **Verification Intent:** Verify hardware recovery when the stream source asserts `TLAST` before the descriptor length is satisfied: DUT enters `STATE_FINISH_BURST`, pads remaining in-flight burst beats with `WSTRB = 4'b0000`, satisfies AXI slave burst requirements without hanging, and reports actual transferred bytes in status.
* **Stimulus Configuration:**
  - Write Descriptor: `dest_addr = 0x2000`, `buffer_len = 64 bytes` (16 beats, `AWLEN = 15`), `tag = 8'h0B`.
  - Stream Write VIP: Injects only 8 beats (32 bytes) and prematurely asserts `TLAST = 1` on beat 7!
  - AXI Memory Slave: Normal active responder expecting 16 beats.
* **Scoreboard Checking Logic:**
  - Verify DUT enters `STATE_FINISH_BURST`.
  - Check that beats 0 to 7 have valid data and `WSTRB == 4'b1111`.
  - Check that beats 8 to 15 have `WDATA == 0` and `WSTRB == 4'b0000` (dummy padding).
  - Check that `WLAST == 1` is asserted on beat 15 to fulfill AXI protocol.
  - Verify that memory from byte 32 onwards is unmodified.
  - Verify status reports actual transferred length: `status_len == 32`, `tag == 8'h0B`, `error == 4'd0`.

---

### Scenario 2.8: Excess Stream Data Draining (STATE_DROP_DATA)
* **Scenario ID:** `S2MM_SCEN_08`
* **Verification Intent:** Verify that when the stream source provides more data than the descriptor buffer length, the DMA writes only the requested length, enters `STATE_DROP_DATA`, keeps `TREADY = 1` to drain excess stream beats until `TLAST`, prevents buffer overflow into adjacent memory, and reports the exact allocated length in status.
* **Stimulus Configuration:**
  - Write Descriptor: `dest_addr = 0x2000`, `buffer_len = 32 bytes` (8 beats), `tag = 8'h0C`.
  - Stream Write VIP: Sends 1 oversized packet of 24 beats (96 bytes = 8 valid beats + 16 excess beats) with `TLAST = 1` on beat 23.
  - AXI Memory Slave: Normal active responder.
* **Scoreboard Checking Logic:**
  - Check that DUT generates exactly one AXI write burst with `AWLEN = 7` (8 beats = 32 bytes).
  - Check that only the first 8 stream beats are written to memory: `axi_wdata[0:7] == stream_tdata[0:7]`.
  - Check that zero AXI writes occur for stream beats 8 to 23 (memory at `0x2020` onwards is untouched).
  - Check that the DMA successfully sinks all 24 stream beats without hanging the stream interface (`TREADY` asserted).
  - Check that completion status reports `status_len == 32`, `tag == 8'h0C`, and `error == 4'd0`.

---

### Scenario 2.9: Memory Bus Write Backpressure (AWREADY & WREADY Stalls)
* **Scenario ID:** `S2MM_SCEN_09`
* **Verification Intent:** Verify that when the memory slave inserts backpressure on `AWREADY` or `WREADY`, the DMA throttles ingress stream `TREADY` and resumes without dropping or duplicating data.
* **Stimulus Configuration:**
  - Write Descriptor: `dest_addr = 0x2000`, `buffer_len = 128 bytes` (32 beats), `tag = 8'h0D`.
  - Stream Write VIP: Continuously produces beats with zero delay.
  - AXI Memory Slave: Injects random 3–8 cycle stalls on `AWREADY` and deasserts `WREADY` every 4 beats.
* **Scoreboard Checking Logic:**
  - Verify that when internal write buffers stall, DUT deasserts `s_axis_write_data_tready`.
  - Check that all 32 beats are correctly written to memory without dropped beats or data corruption.
  - Check that status reports `status_len == 128` and `tag == 8'h0D`.

---

### Scenario 2.10: Bus Write Error Propagation (BRESP = SLVERR & DECERR)
* **Scenario ID:** `S2MM_SCEN_10`
* **Verification Intent:** Verify that when the memory slave returns write response errors (`BRESP = SLVERR` or `DECERR`) on the B channel, the error is latched by `bresp_reg` and reported accurately on the descriptor completion status pulse.
* **Stimulus Configuration:**
  - Sub-iter A (SLVERR):
    - Write Descriptor: `dest_addr = 0x2000`, `buffer_len = 64 bytes`, `tag = 8'h0E`.
    - Stream Write VIP: Sends 16 beats.
    - AXI Memory Slave: Returns `BRESP = 2'b10` (SLVERR) on B channel.
  - Sub-iter B (DECERR):
    - Write Descriptor: `dest_addr = 0x3000`, `buffer_len = 64 bytes`, `tag = 8'h0F`.
    - Stream Write VIP: Sends 16 beats.
    - AXI Memory Slave: Returns `BRESP = 2'b11` (DECERR) on B channel.
* **Scoreboard Checking Logic:**
  - For Sub-iter A: Check that completion status pulses with `tag == 8'h0E` and `error == 4'd6` (`DMA_ERROR_AXI_WR_SLVERR`).
  - For Sub-iter B: Check that completion status pulses with `tag == 8'h0F` and `error == 4'd7` (`DMA_ERROR_AXI_WR_DECERR`).
  - Verify that the DMA clears error flags and returns to `STATE_IDLE` ready for the next transfer.

---

# Feature 3: Full-Duplex Subsystem Concurrency & Multi-Channel Stress

### Scenario 3.1: Nominal Concurrent Full-Duplex Operation
* **Scenario ID:** `FD_SCEN_01`
* **Verification Intent:** Verify concurrent bidirectional data transfer where MM2S (Read Engine) and S2MM (Write Engine) execute simultaneously with zero wait-states without bus starvation or resource interference.
* **Stimulus Configuration:**
  - Read Descriptor: `start_addr = 0x1000`, `xfer_len = 64 bytes` (16 beats), `tag = 8'h10`.
  - Write Descriptor: `dest_addr = 0x2000`, `buffer_len = 64 bytes` (16 beats), `tag = 8'h20`.
  - Stream Interfaces: MM2S egress stream `TREADY = 1`; S2MM ingress stream injects 16 beats continuously with `TLAST` on beat 15.
  - AXI Memory Slave: Zero wait-states on all read (`ARREADY=1`, `RVALID=1`) and write (`AWREADY=1`, `WREADY=1`, `BVALID=1`) channels.
* **Scoreboard Checking Logic:**
  - Concurrently track MM2S stream egress and S2MM memory write beats against respective reference sources.
  - Check that read status pulses with `tag == 8'h10`, `status_len == 64`, and `error == 4'd0`.
  - Check that write status pulses with `tag == 8'h20`, `status_len == 64`, and `error == 4'd0`.
  - Verify zero cross-talk, data leakage, or address confusion between read and write channels.

---

### Scenario 3.2: Concurrent Multi-Burst Slicing & Boundary Crossing
* **Scenario ID:** `FD_SCEN_02`
* **Verification Intent:** Verify simultaneous execution of multi-burst sliced transfers (>64 bytes) and 4KB page boundary crossings on both engines in parallel, validating that both FSM loopback mechanisms operate independently without deadlock.
* **Stimulus Configuration:**
  - Read Descriptor: `start_addr = 0x0FE0`, `xfer_len = 128 bytes` (crosses 4KB page at `0x1000`, sliced into 32B + 64B + 32B bursts), `tag = 8'h11`.
  - Write Descriptor: `dest_addr = 0x2FE0`, `buffer_len = 128 bytes` (crosses 4KB page at `0x3000`, sliced into 32B + 64B + 32B bursts), `tag = 8'h21`.
  - Stream Interfaces: Zero-delay streaming on both sides (32 beats each).
  - AXI Memory Slave: Responds to interleaved multi-burst read (`AR`) and write (`AW`) requests legally.
* **Scoreboard Checking Logic:**
  - Verify that MM2S generates 3 legal AR bursts across the 4KB boundary and assembles exactly 32 stream beats (`TLAST` on beat 31).
  - Verify that S2MM generates 3 legal AW bursts across the 4KB boundary and writes exactly 32 beats to memory.
  - Confirm both engines retire with correct tags (`8'h11` and `8'h21`), lengths (`128`), and `error == 4'd0`.

---

### Scenario 3.3: Asymmetric Cross-Stall & Channel Independence
* **Scenario ID:** `FD_SCEN_03`
* **Verification Intent:** Verify true physical channel independence between AXI Read and Write channels by heavily freezing one engine while the other runs at full wire speed, in both directions (no head-of-line blocking or cross-channel starvation).
* **Stimulus Configuration:**
  - Sub-iter A (Choked Read, High-Speed Write):
    - Read Descriptor: `start_addr = 0x1000`, `xfer_len = 128 bytes`, `tag = 8'h12`. Egress stream `TREADY` held low for 60 cycles.
    - Write Descriptor: `dest_addr = 0x2000`, `buffer_len = 128 bytes`, `tag = 8'h22`. Memory write channels run at 100% wire speed (0 wait-states).
  - Sub-iter B (Choked Write, High-Speed Read):
    - Read Descriptor: `start_addr = 0x1000`, `xfer_len = 128 bytes`, `tag = 8'h13`. Stream `TREADY = 1`, read channels unthrottled.
    - Write Descriptor: `dest_addr = 0x2000`, `buffer_len = 128 bytes`, `tag = 8'h23`. Memory slave holds `AWREADY = 0` and `WREADY = 0` for 60 cycles.
* **Scoreboard Checking Logic:**
  - For Sub-iter A: S2MM write must complete and pulse status while MM2S is still frozen; when `TREADY` is released, MM2S completes cleanly without data loss.
  - For Sub-iter B: MM2S read must complete and pulse status at wire speed without waiting for S2MM; when write channels open, S2MM completes without dropping beats.

---

### Scenario 3.4: Dual-Sided Distributed Random Stalls & Jitter
* **Scenario ID:** `FD_SCEN_04`
* **Verification Intent:** Stress internal elastic buffers, skid registers, and handshake state machines by running concurrent full-duplex transfers under heavy, randomized cycle-by-cycle wait states injected on every AXI channel and Stream interface.
* **Stimulus Configuration:**
  - Read Descriptor: `start_addr = 0x1000`, `xfer_len = 256 bytes` (64 beats), `tag = 8'h14`.
  - Write Descriptor: `dest_addr = 0x3000`, `buffer_len = 256 bytes` (64 beats), `tag = 8'h24`.
  - AXI Memory Slave: Injects randomized 1–5 cycle wait states on `ARREADY`, `RVALID`, `AWREADY`, `WREADY`, and `BVALID`.
  - Stream VIPs: MM2S driver injects random `TREADY` drops; S2MM driver injects random `TVALID` bubbles.
* **Scoreboard Checking Logic:**
  - Verify every single handshake satisfies AXI and AXIS protocol rules (`VALID` remains asserted until `READY` is high; payload stays stable).
  - Compare all 64 read beats and 64 write beats bit-by-bit against expected reference data.
  - Verify no buffer overflows, lost beats, or deadlock conditions occur under continuous jitter.
  - Confirm both status pulses assert with `status_len == 256`, correct tags, and `error == 4'd0`.

---

### Scenario 3.5: Concurrent Fault Isolation & Error Reporting
* **Scenario ID:** `FD_SCEN_05`
* **Verification Intent:** Verify that abnormal fault conditions occurring concurrently or staggered on one engine (e.g., AXI bus error) do not corrupt the operational state, data integrity, or status reporting of the concurrent engine.
* **Stimulus Configuration:**
  - Read Descriptor: `start_addr = 0x1000`, `xfer_len = 64 bytes`, `tag = 8'h15`. Memory slave injects `RRESP = SLVERR` on beat 8.
  - Write Descriptor: `dest_addr = 0x2000`, `buffer_len = 64 bytes`, `tag = 8'h25`. Stream write VIP sends normal 16 beats; memory slave returns `BRESP = OKAY`.
* **Scoreboard Checking Logic:**
  - Verify that MM2S terminates its burst, latches `rresp_reg`, and pulses read status with `tag == 8'h15` and `error == 4'd4` (`DMA_ERROR_AXI_RD_SLVERR`).
  - Verify that S2MM completes successfully with `tag == 8'h25`, `status_len == 64`, and `error == 4'd0` without being contaminated by the read engine's bus error.
  - Verify that both engines return cleanly to their respective `IDLE` states ready for subsequent transactions.
