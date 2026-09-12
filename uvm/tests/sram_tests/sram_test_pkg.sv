// File: sram_test_pkg.sv
// Description: Package bundling all UVM test classes for SRAM Standalone verification.

`ifndef SRAM_TEST_PKG_SV
`define SRAM_TEST_PKG_SV

package sram_test_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import tb_params_pkg::*;
    import axi_mm_pkg::*;
    import axi_ram_env_pkg::*;
    import sram_seq_pkg::*;

    `include "sram_base_test.sv"
    `include "axi_sanity_test.sv"

endpackage : sram_test_pkg

`endif // SRAM_TEST_PKG_SV
