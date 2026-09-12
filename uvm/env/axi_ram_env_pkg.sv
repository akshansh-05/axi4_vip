// File: axi_ram_env_pkg.sv
// Description: Package bundling all components for Standalone SRAM verification.

`ifndef AXI_RAM_ENV_PKG_SV
`define AXI_RAM_ENV_PKG_SV

package axi_ram_env_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import tb_params_pkg::*;
    import axi_mm_pkg::*;

    `include "axi_coverage.sv"
    `include "axi_scoreboard.sv"
    `include "axi_ram_env.sv"

endpackage : axi_ram_env_pkg

`endif // AXI_RAM_ENV_PKG_SV
