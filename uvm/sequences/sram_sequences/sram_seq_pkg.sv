// File: sram_seq_pkg.sv
// Description: Package bundling all stimulus sequences for SRAM Standalone verification.

`ifndef SRAM_SEQ_PKG_SV
`define SRAM_SEQ_PKG_SV

package sram_seq_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import tb_params_pkg::*;
    import axi_mm_pkg::*;

    `include "axi_sanity_seq.sv"

endpackage : sram_seq_pkg

`endif // SRAM_SEQ_PKG_SV
