// File: axi_env.sv
// Top verification environment instantiating the AXI-MM Agent and Coverage Model.

`ifndef AXI_ENV_SV
`define AXI_ENV_SV

class axi_env #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_env;

    typedef axi_wr_agent   #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) wr_agent_type;
    typedef axi_rd_agent   #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) rd_agent_type;
    typedef axi_coverage   #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) cov_type;
    // typedef axi_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) scb_type;

    wr_agent_type axi_wr_agent;
    rd_agent_type axi_rd_agent;
    cov_type      cov;
    // scb_type      scb;

    `uvm_component_param_utils(axi_env #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axi_wr_agent = wr_agent_type::type_id::create("axi_wr_agent", this);
        axi_rd_agent = rd_agent_type::type_id::create("axi_rd_agent", this);
        cov          = cov_type::type_id::create("cov", this);
        // scb          = scb_type::type_id::create("scb", this);
    endfunction : build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Connect both Write and Read Monitor analysis ports to Coverage Subscriber
        axi_wr_agent.mon.ap.connect(cov.analysis_export);
        axi_rd_agent.mon.ap.connect(cov.analysis_export);
        // axi_wr_agent.mon.ap.connect(scb.analysis_export);
        // axi_rd_agent.mon.ap.connect(scb.analysis_export);
    endfunction : connect_phase

endclass : axi_env

`endif // AXI_ENV_SV
