// File: dma_wr_desc_monitor.sv
// Description: UVM Monitor for Write Descriptor Channel. Passively snoops
//              write descriptor commands and status completions, publishing
//              reconstructed transactions via analysis port.

`ifndef DMA_WR_DESC_MONITOR_SV
`define DMA_WR_DESC_MONITOR_SV

class dma_wr_desc_monitor #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_monitor;

    typedef dma_desc_seq_item     #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;
    typedef dma_desc_agent_config #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) cfg_type;

    virtual dma_desc_if #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) vif;
    cfg_type cfg;

    uvm_analysis_port #(item_type) ap;

    `uvm_component_param_utils(dma_wr_desc_monitor #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "dma_wr_desc_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("WR_DESC_MON_CFG", "Failed to get dma_desc_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        // Skeleton monitor for topology verification
    endtask : run_phase

endclass : dma_wr_desc_monitor

`endif // DMA_WR_DESC_MONITOR_SV
