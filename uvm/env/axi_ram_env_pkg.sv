// File: axi_ram_env_pkg.sv
// Description: Package bundling all components for Standalone SRAM verification.

`ifndef AXI_RAM_ENV_PKG_SV
`define AXI_RAM_ENV_PKG_SV

package axi_ram_env_pkg;

    import uvm_pkg::*; // uvm library
    `include "uvm_macros.svh" // uvm macros 

    import tb_params_pkg::*; // tb top parameters
    import axi_mm_pkg::*;  // vip 

    `include "axi_coverage.sv" // coverage model 
    `include "axi_scoreboard.sv" // uvm scoreboard
    `include "axi_ram_env.sv" // ram env 

endpackage : axi_ram_env_pkg

`endif // AXI_RAM_ENV_PKG_SV
