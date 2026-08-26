// File: axi_test_pkg.sv
// Package bundling all UVM Test classes.

`ifndef AXI_TEST_PKG_SV
`define AXI_TEST_PKG_SV

package axi_test_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import tb_params_pkg::*;
    import axi_mm_pkg::*;
    import axi_env_pkg::*;

    `include "base_test.sv"
    `include "axi_sanity_test.sv"

endpackage : axi_test_pkg

`endif // AXI_TEST_PKG_SV
