// File: dma_test_pkg.sv
// Description: Package bundling all UVM test classes for DMA Standalone and Subsystem verification.

`ifndef DMA_TEST_PKG_SV
`define DMA_TEST_PKG_SV

package dma_test_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import tb_params_pkg::*;
    import axi_mm_pkg::*;
    import dma_desc_pkg::*;
    import dma_subsystem_env_pkg::*;

    `include "dma_base_test.sv"

endpackage : dma_test_pkg

`endif // DMA_TEST_PKG_SV
