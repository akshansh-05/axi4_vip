# ASIC Synthesis Reports Directory (166 MHz Target)

This directory stores the official synthesis Quality-of-Results (QoR) reports produced by **Cadence Genus Synthesis Solution** targeting maximum operating frequency (**166.0 MHz**, clock period $T_{clk} = 6.024\text{ ns}$).

## Expected Report Deliverables

When performing the synthesis run (`./run_synth.sh` or `genus -files synth.tcl`), drop your generated reports directly here:

| Report File | Purpose | Key Metrics Checked |
| :--- | :--- | :--- |
| `timing.rpt` | Static Timing Analysis (STA) | Worst Negative Slack (WNS), critical carry-propagation path, setup margin |
| `area.rpt` | Hierarchical Area Breakdown | Gate area ($\mu\text{m}^2$) and cell counts for `axi_dma`, `axi_dma_rd`, `axi_dma_wr` |
| `qor.rpt` | Quality-of-Results Matrix | Target frequency (166 MHz), slack closure, runtime, peak memory |
| `power.rpt` | Dynamic & Static Power | Internal, switching, and static leakage power at 166 MHz |
| `gates.rpt` | Standard Cell Breakdown | Sequential flip-flops (`fflopd`), combinational logic (`nand2`, `nor2`), buffers |
| `check_design.rpt` | Structural Lint Audit | Unresolved pins, floating nets, inferred latches (must be 0) |

Once you place your `.rpt` / `.txt` files here, the summary tables in [ASIC_IMPLEMENTATION_AND_COVERAGE_RESULTS.md](file:///c:/Users/admin/OneDrive/Desktop/axi_vip_project/axi4_vip/asic/ASIC_IMPLEMENTATION_AND_COVERAGE_RESULTS.md) will be updated with the final 166 MHz numbers.
