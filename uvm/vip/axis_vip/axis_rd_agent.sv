// File: axis_rd_agent.sv
// Description: Dedicated UVM Agent for AXI4-Stream Read Channel (Slave / Consumer).

`ifndef AXIS_RD_AGENT_SV
`define AXIS_RD_AGENT_SV

class axis_rd_agent #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_agent;

    typedef axis_agent_config #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) cfg_type;
    typedef axis_rd_driver    #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) drv_type;
    typedef axis_rd_monitor   #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) mon_type;
    typedef axis_sequencer    #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) seqr_type;

    cfg_type  cfg;
    drv_type  drv;
    mon_type  mon;
    seqr_type seqr;

    `uvm_component_param_utils(axis_rd_agent #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "axis_rd_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("AXIS_RD_AGT_CFG", "Failed to get axis_agent_config from config_db")
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

endclass : axis_rd_agent

`endif // AXIS_RD_AGENT_SV
