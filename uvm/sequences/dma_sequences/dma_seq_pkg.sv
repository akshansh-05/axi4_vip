// File: dma_seq_pkg.sv
// Description: Package bundling all DMA descriptor sequence classes.

`ifndef DMA_SEQ_PKG_SV
`define DMA_SEQ_PKG_SV

package dma_seq_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import tb_params_pkg::*;
    import dma_desc_pkg::*;

    `include "dma_desc_sanity_seq.sv"

endpackage : dma_seq_pkg

`endif // DMA_SEQ_PKG_SV