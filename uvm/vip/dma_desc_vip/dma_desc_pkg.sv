// File: dma_desc_pkg.sv
// Description: Package bundling all DMA Descriptor VIP components.

`ifndef DMA_DESC_PKG_SV
`define DMA_DESC_PKG_SV

package dma_desc_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "dma_desc_seq_item.sv"
    `include "dma_desc_agent_config.sv"
    `include "dma_desc_sequencer.sv"
    `include "dma_rd_desc_driver.sv"
    `include "dma_wr_desc_driver.sv"
    `include "dma_rd_desc_monitor.sv"
    `include "dma_wr_desc_monitor.sv"
    `include "dma_rd_desc_agent.sv"
    `include "dma_wr_desc_agent.sv"

endpackage : dma_desc_pkg

`endif // DMA_DESC_PKG_SV
