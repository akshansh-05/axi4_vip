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
    `include "dma_rd_desc_nominal_seq.sv"
    `include "dma_rd_desc_multiburst_seq.sv"
    `include "dma_rd_desc_4kb_split_seq.sv"
    `include "dma_rd_desc_unaligned_seq.sv"
    `include "dma_rd_desc_partial_len_seq.sv"
    `include "dma_rd_desc_backpressure_seq.sv"

endpackage : dma_seq_pkg

`endif // DMA_SEQ_PKG_SV
