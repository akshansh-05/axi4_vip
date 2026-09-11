// File: dma_desc_agent_config.sv
// Description: Configuration object for DMA Descriptor Agent controlling
//              active/passive mode and providing the virtual interface handle.

`ifndef DMA_DESC_AGENT_CONFIG_SV
`define DMA_DESC_AGENT_CONFIG_SV

class dma_desc_agent_config #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_object;

    // Active (Driver + Monitor + Sequencer) or Passive (Monitor only)
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // Virtual interface handle to dma_desc_if
    virtual dma_desc_if #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) vif;

    `uvm_object_param_utils(dma_desc_agent_config #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "dma_desc_agent_config");
        super.new(name);
    endfunction : new

endclass : dma_desc_agent_config

`endif // DMA_DESC_AGENT_CONFIG_SV
