// File: dma_rd_desc_driver.sv
// Description: UVM Driver for Read Descriptor Channel (MM2S: Memory-to-Stream).
//              Drives descriptor command requests and handles global read_enable.

`ifndef DMA_RD_DESC_DRIVER_SV
`define DMA_RD_DESC_DRIVER_SV

class dma_rd_desc_driver #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_driver #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item    #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) req_type;
    typedef dma_desc_agent_config #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) cfg_type;

    virtual dma_desc_if #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) vif;
    cfg_type cfg;

    `uvm_component_param_utils(dma_rd_desc_driver #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "dma_rd_desc_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("RD_DESC_DRV_CFG", "Failed to get dma_desc_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        // Skeleton driver for topology verification
    endtask : run_phase

endclass : dma_rd_desc_driver

`endif // DMA_RD_DESC_DRIVER_SV
