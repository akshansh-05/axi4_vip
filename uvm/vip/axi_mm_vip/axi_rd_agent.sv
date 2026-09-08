// File: axi_rd_agent.sv
// Dedicated UVM Agent for AXI4 Memory-Mapped Read Channels (AR, R).

`ifndef AXI_RD_AGENT_SV
`define AXI_RD_AGENT_SV

class axi_rd_agent #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_agent;

    typedef axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) cfg_type;
    typedef axi_rd_driver    #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) drv_type;
    typedef axi_rd_monitor   #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) mon_type;
    typedef axi_sequencer    #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) seqr_type;

    cfg_type  cfg;
    drv_type  drv;
    mon_type  mon;
    seqr_type seqr;

    `uvm_component_param_utils(axi_rd_agent #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_rd_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("RD_AGT_CFG", "Failed to get axi_agent_config from config_db")
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

endclass : axi_rd_agent

`endif // AXI_RD_AGENT_SV
