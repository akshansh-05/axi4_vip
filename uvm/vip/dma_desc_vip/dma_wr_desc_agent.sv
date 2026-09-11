// File: dma_wr_desc_agent.sv
// Description: Dedicated UVM Agent for Write Descriptor Channel (S2MM).

`ifndef DMA_WR_DESC_AGENT_SV
`define DMA_WR_DESC_AGENT_SV

class dma_wr_desc_agent #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_agent;

    typedef dma_desc_agent_config #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) cfg_type;
    typedef dma_wr_desc_driver    #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) drv_type;
    typedef dma_wr_desc_monitor   #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) mon_type;
    typedef dma_desc_sequencer    #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) seqr_type;

    cfg_type  cfg;
    drv_type  drv;
    mon_type  mon;
    seqr_type seqr;

    `uvm_component_param_utils(dma_wr_desc_agent #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "dma_wr_desc_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("WR_DESC_AGT_CFG", "Failed to get dma_desc_agent_config from config_db")
        end

        mon = mon_type::type_id::create("mon", this);

        if (cfg.is_active == UVM_ACTIVE) begin
            drv  = drv_type::type_id::create("drv", this);
            seqr = seqr_type::type_id::create("seqr", this);
        end
    endfunction : build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        if (cfg.is_active == UVM_ACTIVE) begin
            drv.seq_item_port.connect(seqr.seq_item_export);
        end
    endfunction : connect_phase

endclass : dma_wr_desc_agent

`endif // DMA_WR_DESC_AGENT_SV
