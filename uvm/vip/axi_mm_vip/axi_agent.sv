// File: axi_agent.sv
// UVM Agent encapsulating Driver, Monitor, and Sequencer for AXI4-MM bus.

`ifndef AXI_AGENT_SV
`define AXI_AGENT_SV

class axi_agent #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_agent;

    typedef axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) cfg_type;
    typedef axi_driver       #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) drv_type;
    typedef axi_monitor      #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) mon_type;
    typedef axi_sequencer    #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) seqr_type;

    cfg_type  cfg;
    drv_type  drv;
    mon_type  mon;
    seqr_type seqr;

    `uvm_component_param_utils(axi_agent #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("AGT_CFG", "Failed to get axi_agent_config from config_db")
        end

        // Monitor is always instantiated in both active and passive modes
        mon = mon_type::type_id::create("mon", this);

        // Driver and Sequencer are created only in active mode
        if (cfg.is_active == UVM_ACTIVE) begin
            drv  = drv_type::type_id::create("drv", this);
            seqr = seqr_type::type_id::create("seqr", this);
        end
    endfunction : build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect driver to sequencer in active mode
        if (cfg.is_active == UVM_ACTIVE) begin
            drv.seq_item_port.connect(seqr.seq_item_export);
        end
    endfunction : connect_phase

endclass : axi_agent

`endif // AXI_AGENT_SV
