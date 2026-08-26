// File: axi_mm_pkg.sv
// Package bundling all AXI4 Memory-Mapped (AXI-MM) UVC components.

`ifndef AXI_MM_PKG_SV
`define AXI_MM_PKG_SV

package axi_mm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "axi_seq_item.sv"
    `include "axi_agent_config.sv"
    `include "axi_driver.sv"
    `include "axi_monitor.sv"
    `include "axi_sequencer.sv"
    `include "axi_agent.sv"

    // Sequences
    `include "sequences/axi_sanity_seq.sv"

endpackage : axi_mm_pkg

`endif // AXI_MM_PKG_SV
