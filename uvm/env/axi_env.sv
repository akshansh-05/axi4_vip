// File: axi_env.sv
// Top verification environment instantiating the AXI-MM Agent.

`ifndef AXI_ENV_SV
`define AXI_ENV_SV

class axi_env #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_env;

    typedef axi_agent #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) agent_type;

    agent_type axi_agent;

    `uvm_component_param_utils(axi_env #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axi_agent = agent_type::type_id::create("axi_agent", this);
    endfunction : build_phase

endclass : axi_env

`endif // AXI_ENV_SV
