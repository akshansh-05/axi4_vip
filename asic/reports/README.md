# ASIC Synthesis Reports Directory

This directory stores the official synthesis Quality-of-Results (QoR) reports produced by **Cadence Genus Synthesis Solution**.

## Directory Layout
* `100mhz/`: Baseline synthesis reports ($T_{clk} = 10.0\text{ ns}$, 100 MHz).
* `166mhz/`: Stress synthesis reports ($T_{clk} = 6.024\text{ ns}$, 166 MHz, maximum operating frequency target).

## Expected Report Files
When performing a synthesis run, the following report files are generated:

| Report File | Purpose | Key Metrics |
| :--- | :--- | :--- |
| `timing.rpt` | Static Timing Analysis (STA) | Setup Worst Negative Slack (WNS), critical data arrival path, startpoint/endpoint |
| `area.rpt` | Hierarchical Area Breakdown | Cell count, module area ($\mu\text{m}^2$) for `axi_dma`, `axi_dma_rd`, `axi_dma_wr` |
| `qor.rpt` | Quality of Results Matrix | Target frequency, cell count, WNS, total negative slack, runtime, memory |
| `power.rpt` | Power Estimation | Dynamic switching power, internal cell power, static leakage power |
| `gates.rpt` | Standard Cell Breakdown | Counts of DFFs (`fflopd`), NAND gates (`nand2`), NOR, inverters, arithmetic gates |
| `check_design.rpt` | Structural Lint Audit | Unresolved references, multi-driven nets, inferred latches (must be zero) |

You can drop the `.txt` or `.rpt` files directly into `166mhz/` or `100mhz/` after executing the synthesis run.
