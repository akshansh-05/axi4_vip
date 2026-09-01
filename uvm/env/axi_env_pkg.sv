// File: axi_env_pkg.sv
// Package bundling the top environment components.

`ifndef AXI_ENV_PKG_SV
`define AXI_ENV_PKG_SV

package axi_env_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import tb_params_pkg::*;
    import axi_mm_pkg::*;

    `include "axi_coverage.sv"
    `include "axi_env.sv"

endpackage : axi_env_pkg

`endif // AXI_ENV_PKG_SV
