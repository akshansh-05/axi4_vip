// File: dma_desc_sequencer.sv
// Description: UVM Sequencer specialized for DMA descriptor items.

`ifndef DMA_DESC_SEQUENCER_SV
`define DMA_DESC_SEQUENCER_SV

class dma_desc_sequencer #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequencer #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    `uvm_component_param_utils(dma_desc_sequencer #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "dma_desc_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

endclass : dma_desc_sequencer

`endif // DMA_DESC_SEQUENCER_SV
