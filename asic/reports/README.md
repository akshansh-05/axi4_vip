# Cadence Genus ASIC Synthesis Reports (166.67 MHz Nominal Target)

This directory contains the official post-synthesis Quality of Results (QoR) reports produced by **Cadence Genus™ Synthesis Solution (v20.11-s111_1)** targeting the **AMBA AXI4 Direct Memory Access (DMA) Subsystem** (`axi_dma`) at a nominal clock frequency of **166.67 MHz** ($T_{clk} = 6.000\text{ ns}$ / $6{,}000\text{ ps}$).

The synthesis run executed on `cadence-server.snu.in` using standard cell library `tutorial.lib` under nominal operating conditions (`typical_case`, balanced tree, `AL_LARGE` wireload model).

## 1. Synthesis Deliverables Index

| Report File | Tool Command / Source | Primary Verification & QoR Focus | Status |
| :--- | :--- | :--- | :---: |
| `qor.rpt` | `report_qor` | Global Quality-of-Results dashboard: timing slack, cell count, runtime, peak memory | **PASSED** |
| `timing.rpt` | `report_timing` | Static Timing Analysis (STA): setup slack (+836.1 ps), data arrival, critical path stages | **MET** |
| `area.rpt` | `report_area` | Hierarchical silicon area breakdown for top-level `axi_dma` and write/read sub-engines | **CLOSED** |
| `gates.rpt` | `report_gates` | Cell-type classification: sequential registers (`fflopd`), logic (`nand2`, `nor2`), inverters | **VERIFIED** |
| `power.rpt` | `report_power` | Dynamic switching power breakdown across combinational logic and registers (150.86 mW) | **ANALYZED** |
| `check_design.rpt` | `check_design -unresolved` | Structural lint audit: unresolved references, empty modules, and inferred latches (0 latches) | **CLEAN** |

## 2. Key Synthesis Metrics Dashboard

```
================================================================================
           AXI4 DMA CONTROLLER: CADENCE GENUS SYNTHESIS DASHBOARD
================================================================================
  Target Clock Period (T_clk)     :  6000.0 ps (6.000 ns / 166.67 MHz)
  Setup Timing Status             :  MET (Worst Negative Slack: +836.1 ps)
  Total Negative Slack (TNS)      :  0.0 ps (0 Violating Paths)
  Critical Path Data Delay        :  3,764 ps (32 logic levels)
  Total Input Arrival Delay       :  4,964 ps (Input Delay: 1,200 ps)
  Required Arrival Time           :  5,800 ps (Setup: 100 ps, Uncertainty: 100 ps)
  Achievable Theoretical F_max    :  193.65 MHz (Min Period: 5.164 ns)
  Total Leaf Instance Count       :  30,749 cells
  Sequential Instance Count       :  4,652 flip-flops (fflopd: 27,912.0 μm², 51.1%)
  Combinational Instance Count    :  26,097 gates (26,700.0 μm², 48.9%)
  Total Silicon Cell Area         :  54,612.000 μm² (~0.055 mm²)
  Write Sub-Engine (axi_dma_wr)   :  34,648.500 μm² (63.45% of total area, 19,614 cells)
  Read Sub-Engine (axi_dma_rd)    :  19,963.500 μm² (36.55% of total area, 11,135 cells)
  Total Dynamic Power             :  150.86 mW (1.50856e-01 W at 166.67 MHz)
  Combinational Logic Power       :  113.41 mW (75.18% of dynamic power)
  Sequential Register Power       :  37.45 mW (24.82% of dynamic power)
  Structural Design Audit         :  0 Unresolved References, 0 Empty Modules, 0 Latches
  Synthesis Wall Clock Runtime    :  303.25 seconds (Elapsed: 331 seconds)
  Genus Peak Memory Consumption   :  1,638.28 MB
  Execution Hostname              :  cadence-server.snu.in
================================================================================
```

## 3. Detailed Report Breakdown

### 3.1 Static Timing Analysis (`timing.rpt`)
* **Endpoint:** `axi_dma_wr_inst/status_fifo_len_reg[31][19]/D` (Rising clock capture).
* **Startpoint:** `s_axis_write_data_tkeep[2]` (Rising clock launch).
* **Setup Slack Formulation:**
  $$\text{Slack} = T_{\text{required}} - T_{\text{arrival}} = 5{,}800\text{ ps} - 4{,}964\text{ ps} = \mathbf{+836.1\text{ ps}}$$
* **Path Analysis:** The critical path originates from the ingress stream byte-strobe input `s_axis_write_data_tkeep[2]` ($1{,}200\text{ ps}$ input delay budget), propagates through the write engine's byte adder network (`ADD_TC_OP_3_Y_final_adder` across 32 logic gate levels), and terminates at the MSB of the descriptor tracking status FIFO length register.
* **Timing Margin:** Positive setup slack of **+836.1 ps** provides a **13.9% timing safety margin** over the 6.0 ns clock period, accommodating back-end place-and-route clock skew, jitter, and interconnect RC parasitic degradation.

### 3.2 Hierarchical Area Breakdown (`area.rpt`)
* **Top-Level `axi_dma`:** $54{,}612.000\ \mu\text{m}^2$ across 30,749 cells.
* **S2MM Write Sub-Engine (`axi_dma_wr_inst`):** $34{,}648.500\ \mu\text{m}^2$ (63.45% of total silicon area, 19,614 cells). The write engine occupies greater area due to the 2-cycle distributed RAM output skid FIFO (`out_fifo`), 5-state master control FSM with corner-case zero-padding and packet draining states, 32-bit unaligned write barrel shifter, and 32-entry write status tracking FIFO.
* **MM2S Read Sub-Engine (`axi_dma_rd` by subtraction):** $19{,}963.500\ \mu\text{m}^2$ (36.55% of total silicon area, 11,135 cells). Implements dual 2-state FSMs, registered command pipeline FIFO, 32-bit unaligned read barrel shifter, and 4KB address clamp logic.

### 3.3 Standard Cell Breakdown (`gates.rpt`)

| Cell Name | Gate Function | Instances | Total Area ($\mu\text{m}^2$) | Area % | Library |
| :--- | :--- | :---: | :---: | :---: | :---: |
| `fflopd` | D-Type Flip-Flop with Reset | 4,652 | 27,912.000 | 51.1% | `tutorial` |
| `nand2` | 2-Input NAND Gate | 22,722 | 22,722.000 | 41.6% | `tutorial` |
| `nor2` | 2-Input NOR Gate | 1,869 | 2,803.500 | 5.1% | `tutorial` |
| `inv1` | Single Inverter | 1,225 | 612.500 | 1.1% | `tutorial` |
| `xor2` | 2-Input XOR Gate | 281 | 562.000 | 1.0% | `tutorial` |
| **Total** | **All Standard Cells** | **30,749** | **54,612.000** | **100.0%** | `tutorial` |

### 3.4 Dynamic Power Dissipation (`power.rpt`)
* **Total Dynamic Power:** **150.86 mW** ($1.50856 \times 10^{-1}\text{ W}$) at 166.67 MHz nominal clocking.
* **Combinational Logic Switching Power:** **113.41 mW** ($1.13409 \times 10^{-1}\text{ W}$, 75.18% of total power). Driven by high-speed arithmetic adders, multiplexers, and multi-stage barrel shifters.
* **Sequential Register Switching Power:** **37.45 mW** ($3.74468 \times 10^{-2}\text{ W}$, 24.82% of total power). Dissipated across the 4,652 sequential flip-flops.
* **Static Leakage Power:** Evaluated as $0.0\text{ W}$ in the generic CMOS educational cell library model.

### 3.5 Structural Lint & Design Rule Audit (`check_design.rpt`)
* **Unresolved References:** 0 (All hierarchical modules, operators, and library macros resolved).
* **Empty Modules:** 0 (No hollow black boxes).
* **Inferred Latches:** 0 (Zero combinational feedback loops or unintentional level-sensitive latches; 100% synchronous flip-flop implementation).

## 4. Synthesis Reproduction Guide

To reproduce the exact synthesis QoR on Cadence Genus:

```bash
# Method 1: Execute bash driver script directly from the asic directory
cd asic
chmod +x run_synth.sh
./run_synth.sh

# Method 2: Execute Genus directly in batch mode
cd asic
genus -files synth.tcl
```
