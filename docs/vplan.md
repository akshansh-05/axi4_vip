# Verification Plan (vPlan): AXI4 Memory-Mapped RAM & DMA Subsystem

**Document Version:** 1.0  
**Project:** Advanced UVM Verification of AXI4 DMA-SRAM Subsystem  
**Scope:** Part 1 — AXI-RAM Functional Coverage & Verification Baseline  

---

## 1. Executive Summary & Verification Strategy

The primary objective of this verification plan is to achieve **100% functional coverage** and **zero data corruption** across all valid, corner-case, and boundary AXI4 Memory-Mapped transactions on the static RAM slave (`axi_ram.v`).

This document details the **exact mapping** between:
1. **RTL Micro-Architecture & Silicon Mechanisms** inside `axi_ram.v`.
2. **Covergroups & Bins** implemented in `uvm/env/axi_coverage.sv`.
3. **Escaped Bug / Failure Mode Analysis** (what catastrophic hardware bug is prevented by hitting each bin).
4. **Stimulus Scenarios & Checking Criteria**.

---

## 2. AXI-RAM Functional Coverage Model Matrix (`cg_axi_write` & `cg_axi_read`)

```
                                axi_coverage Subscriber
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                        │
│   ┌────────────────────────────────────────┐  ┌─────────────────────────────────────┐  │
│   │       cg_axi_write (AW, W, B)          │  │       cg_axi_read (AR, R)           │  │
│   ├────────────────────────────────────────┤  ├─────────────────────────────────────┤  │
│   │ 1. cp_awlen      (1, 2-16, 17-64, 256) │  │ 1. cp_arlen      (1, 2-16, 17-64,   │  │
│   │ 2. cp_awsize     (1B, 2B, 4B)          │  │                   256)              │  │
│   │ 3. cp_awburst    (FIXED, INCR, WRAP)   │  │ 2. cp_arsize     (1B, 2B, 4B)       │  │
│   │ 4. cp_awaddr_align (+0, +1, +2, +3)    │  │ 3. cp_arburst    (FIXED, INCR, WRAP)│  │
│   │ 5. cp_awaddr_range (Low, Mid, High)    │  │ 4. cp_araddr_align (+0, +1, +2, +3) │  │
│   │ 6. cp_wstrb      (16 Byte-mask combos) │  │ 5. cp_araddr_range (Low, Mid, High) │  │
│   │ 7. cp_awid       (0, Low, Mid, High)   │  │ 6. cp_arid       (0, Low, Mid, High)│  │
│   │ 8. cp_bresp      (OKAY, EXOKAY, ERR)   │  │ 7. cp_rresp      (OKAY, EXOKAY, ERR)│  │
│   ├────────────────────────────────────────┤  ├─────────────────────────────────────┤  │
│   │ 4 Multi-Dimensional Cross Coverages    │  │ 4 Multi-Dimensional Cross Coverages │  │
│   └────────────────────────────────────────┘  └─────────────────────────────────────┘  │
│                                                                                        │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Detailed Coverpoint & Bin Analysis (The "Why Every Bin Matters" Matrix)

### 3.1 Write & Read Burst Length (`cp_awlen` / `cp_arlen`)
* **Hardware Target:** Internal hardware counter `reg [7:0] burst_cnt` and comparator `burst_cnt == burst_len_reg`.

| Bin Name | Value Range | Hardware Mechanism Stimulated | Bug Prevented / Silicon Failure Mode |
| :--- | :---: | :--- | :--- |
| **`single_beat`** | `0` (1 beat) | 1-cycle single transfer. `burst_cnt == 0` is true on initial clock cycle. | **FSM Pipeline Stall:** Slave FSM hangs waiting for a 2nd beat before generating `BVALID`/`RVALID`. |
| **`short_burst`** | `[1:15]` (2–16 beats) | Standard burst counter increment and 4-bit boundary transitions. | **Off-by-One Counter:** Counter stops at $N-1$ beats or produces $N+1$ responses; corrupts CPU cache line fills. |
| **`med_burst`** | `[16:63]` (17–64 beats) | 5th and 6th counter bits (`burst_cnt[5:4]`). | **Bit-Drop Bug:** RTL bug where 8-bit counter `len[7:0]` was accidentally truncated to 4 bits (`len[3:0]`). Transfers $>16$ beats truncate silently. |
| **`long_burst`** | `[64:254]` (65–255 beats) | Extended high-throughput burst streaming. | **FIFO Underflow/Overflow:** Stresses continuous memory array updates without pipeline bubbles. |
| **`max_burst`** | `255` (256 beats) | Maximum 8-bit limit (`8'hFF`). | **Counter Rollover Lockup:** `burst_cnt + 1` overflows $255 \to 0$, causing an **infinite loop lockup** in hardware. |

---

### 3.2 Transfer Size per Beat (`cp_awsize` / `cp_arsize`)
* **Hardware Target:** Address increment adder step `addr <= addr + (1 << size)`.

| Bin Name | Value Range | Hardware Mechanism Stimulated | Bug Prevented / Silicon Failure Mode |
| :--- | :---: | :--- | :--- |
| **`size_1B`** | `3'b000` (1 Byte) | 8-bit narrow transfer address calculation. | **Wrong Address Step:** Adder calculates `addr + 4` instead of `addr + 1`. Writing a single `char` corrupts 4 consecutive memory locations! |
| **`size_2B`** | `3'b001` (2 Bytes) | 16-bit half-word transfer calculation. | **Half-Word Offset Error:** Adder jumps by $+4$ instead of $+2$. 16-bit sensor/audio samples get spaced out with corrupted garbage bytes. |
| **`size_4B`** | `3'b010` (4 Bytes) | Full 32-bit bus width transfer. | Standard 32-bit integer access failures. |

---

### 3.3 Burst Type (`cp_awburst` / `cp_arburst`)
* **Hardware Target:** Addressing FSM state machine for `FIXED`, `INCR`, and `WRAP` modes.

| Bin Name | Value Range | Hardware Mechanism Stimulated | Bug Prevented / Silicon Failure Mode |
| :--- | :---: | :--- | :--- |
| **`burst_fixed`** | `2'b00` (FIXED) | Address remains constant across all burst beats. | **Address Drift Bug:** Hardware mistakenly increments address instead of freezing it. Overwrites registers adjacent to FIFOs. |
| **`burst_incr`** | `2'b01` (INCR) | Sequential memory address stepping. | **Missing Increment:** Hardware writes the first address repeatedly instead of filling an array. |
| **`burst_wrap`** | `2'b10` (WRAP) | Address increments until cache-line boundary, then wraps to start. | **Cache Line Runaway:** Hardware fails to wrap back to boundary start and writes past line boundary, corrupting CPU instruction caches. |
| **`illegal_bins rsvd`** | `2'b11` (Reserved) | Protocol violation guard. | **Undefined Hardware State:** Hardware locks up upon receiving illegal protocol codes instead of asserting slave error. |

---

### 3.4 Address Alignment (`cp_awaddr_align` / `cp_araddr_align`)
* **Hardware Target:** Lower address bits `addr[1:0]` decoding and initial beat offset calculation.

| Bin Name | Value Range | Hardware Mechanism Stimulated | Bug Prevented / Silicon Failure Mode |
| :--- | :---: | :--- | :--- |
| **`aligned_word`** | `2'b00` (Offset 0) | Standard 32-bit word aligned address (`0x0`, `0x4`, `0x8`, `0xC`). | Baseline word addressing. |
| **`unaligned_01`** | `2'b01` (Offset +1B) | Start address `0x1001`, `0x1005`. | **Unaligned Start Bug:** Hardware aligns to `0x1000` and drops byte 0, or calculates 2nd beat as `0x1002` instead of `0x1004`. Scrambles network packet headers. |
| **`unaligned_10`** | `2'b10` (Offset +2B) | Start address `0x1002`, `0x1006` (Half-word offset). | Fails to advance to next 32-bit boundary on beat 1. |
| **`unaligned_11`** | `2'b11` (Offset +3B) | Start address `0x1003`, `0x1007` (1 byte in beat 0). | Heavy edge-case pointer arithmetic in software corrupts memory. |

---

### 3.5 Memory Address Range (`cp_awaddr_range` / `cp_araddr_range`)
* **Hardware Target:** Memory array index decoder `mem[addr]`.

| Bin Name | Address Range | Hardware Mechanism Stimulated | Bug Prevented / Silicon Failure Mode |
| :--- | :---: | :--- | :--- |
| **`low_mem`** | `0x0000 : 0x0FFF` | Base address decoding and reset vector page (First 4KB). | Reset/bootloader memory at `0x0000` inaccessible or corrupted. |
| **`mid_mem`** | `0x1000 : 0xEFFF` | General RAM address space. | General memory array decoding errors. |
| **`high_mem`** | `0xF000 : 0xFFFF` | Top 4KB boundary of the 64KB RAM space. | **Address Rollover Bug:** Accessing `0xFFFF` overflows address lines back to `0x0000` and overwrites bootloader code. |

---

### 3.6 Write Byte Strobes (`cp_wstrb`)
* **Hardware Target:** Physical byte-enable write gates `if (wstrb[i]) mem[addr+i] <= wdata[...]`.
* **Sampling Rule:** Evaluated on **every individual beat** across multi-beat bursts via `current_strb`.

| Bin Name | Strobe Patterns | Hardware Mechanism Stimulated | Bug Prevented / Silicon Failure Mode |
| :--- | :--- | :--- | :--- |
| **`full_word`** | `4'b1111` | All 4 byte lanes active simultaneously. | Standard 32-bit write operation. |
| **`three_bytes`** | `4'b0111`, `4'b1110`, `4'b1101`, `4'b1011` | 3 active byte lanes (Unaligned / partial). | **Byte Gate Coupling:** Byte 3 enable is accidentally tied to Byte 2 in silicon; overwrites neighboring struct fields. |
| **`two_bytes`** | `4'b0011`, `4'b1100`, `4'b0110`, `4'b1001`, `4'b0101`, `4'b1010` | 16-bit half-word write isolation. | Updating variable `a` in memory accidentally overwrites adjacent variable `b`. |
| **`single_bytes`** | `4'b0001`, `4'b0010`, `4'b0100`, `4'b1000` | Single byte (8-bit) write isolation. | Setting a 1-byte boolean flag corrupts the other 3 bytes in the word. |
| **`illegal_bins no_write`** | `4'b0000` | Assertion monitor for null writes. | Flags unexpected zero-byte write transfers. |

---

### 3.7 Transaction ID Tags & Response Status (`cp_awid`, `cp_bresp`, `cp_rresp`)
* **Hardware Target:** Response routing registers (`bid <= awid`, `rid <= arid`, `bresp`, `rresp`).

| Coverpoint | Bins | Bug Prevented / Silicon Failure Mode |
| :--- | :--- | :--- |
| **`cp_awid` / `cp_arid`** | `id_zero` (`0`), `id_low` (`1:15`), `id_mid` (`16:239`), `id_high` (`240:255`) | **ID Tag Corruption:** Slave returns wrong ID tag in `BID`/`RID`, causing master to misroute transaction completion. |
| **`cp_bresp` / `cp_rresp`** | `okay` (`2'b00`), `exokay` (`2'b01`), `slverr` (`2'b10`), `decerr` (`2'b11`) | **Status Code Glitch:** Slave returns undefined status codes causing master interconnect exceptions. |

---

## 4. Multi-Dimensional Cross-Coverage Matrix

A single coverpoint only verifies 1 parameter in isolation. Cross-coverage verifies **intersections of complex parameters**:

1. **`cross_awlen_awsize` / `cross_arlen_arsize`**:
   * Stresses long bursts of narrow transfers (e.g. 256 beats of 1-Byte transfers vs 256 beats of 4-Byte transfers).
2. **`cross_awlen_awburst` / `cross_arlen_arburst`**:
   * Stresses long INCR bursts (256 beats) vs wrapping bursts (16 beats).
3. **`cross_awlen_wstrb`**:
   * Stresses multi-beat bursts where byte strobes dynamically change across beats (e.g. partial start beat $\to$ full middle beats $\to$ partial end beat).
4. **`cross_awlen_awalign` / `cross_arlen_aralign`**:
   * Stresses multi-beat bursts starting at unaligned byte offsets (`+1`, `+2`, `+3`).

---

## 5. Test Matrix & Verification Milestones

| Test Name | Stimulus Sequence | Scoreboard Verification | Coverage Target |
| :--- | :--- | :--- | :---: |
| **`axi_sanity_test`** | 4-beat aligned Write burst $\to$ 4-beat Read burst at `0x1000`. | Exact byte match on 4 words. | Baseline connectivity. |
| **`axi_burst_len_test`** | Sweep `len` across 1, 2, 4, 8, 16, 64, 128, 256 beats. | Byte integrity on all burst sizes. | 100% `cp_awlen`, `cp_arlen`. |
| **`axi_narrow_size_test`**| 1B and 2B transfers with incrementing addresses. | Verifies $+1$ and $+2$ address increments. | 100% `cp_awsize`, `cp_arsize`. |
| **`axi_unaligned_addr_test`**| Bursts starting at addresses ending in `0x1`, `0x2`, `0x3`. | Byte-accurate memory layout check. | 100% `cp_awaddr_align`. |
| **`axi_strobe_sweep_test`**| Random strobe masks across 1B, 2B, 3B, 4B active lanes. | Verifies untouched bytes remain unaltered in RAM. | 100% `cp_wstrb`. |
| **`axi_wrap_burst_test`** | 2, 4, 8, 16 beat WRAP bursts at unaligned critical words. | Verifies cache line boundary wrap-around. | 100% `cp_awburst` (WRAP). |
| **`axi_random_stress_test`**| 1000 fully randomized transactions with random delays. | Continuous associative memory checking. | **100% Coverage Sign-Off**. |

---

## 6. Sign-off Criteria

1. **Zero UVM Errors / Fatal Warnings** across all test suites.
2. **100% Functional Coverage** in `cg_axi_write` and `cg_axi_read` (including all cross-coverage items).
3. **100% Code Coverage** (Line, Condition, FSM State, Branch, and Toggle on `axi_ram.v`).
