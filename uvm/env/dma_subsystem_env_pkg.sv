// File: dma_subsystem_env_pkg.sv
// Description: Package bundling the top DMA Subsystem environment components.

`ifndef DMA_SUBSYSTEM_ENV_PKG_SV
`define DMA_SUBSYSTEM_ENV_PKG_SV

package dma_subsystem_env_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import tb_params_pkg::*;
    import axi_mm_pkg::*;
    import dma_desc_pkg::*;
    import axi_ram_env_pkg::*;

    `include "dma_subsystem_env.sv"

endpackage : dma_subsystem_env_pkg

`endif // DMA_SUBSYSTEM_ENV_PKG_SV
