// File: axi_agent_config.sv
// Configuration object for AXI-MM Agent controlling active/passive mode and master/slave role.

`ifndef AXI_AGENT_CONFIG_SV
`define AXI_AGENT_CONFIG_SV

class axi_agent_config #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_object;

    // Active (Driver + Monitor) or Passive (Monitor only)
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // Master mode (drives AW/W/AR) vs Slave mode (responds with B/R)
    bit is_master = 1'b1;

    // Instantiate the Virtual interface handle
    virtual axi_if #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) vif;

`uvm_object_param_utils(axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

function new(string name = "axi_agent_config");
   super.new(name);
endfunction : new

endclass : axi_agent_config

`endif // AXI_AGENT_CONFIG_SV
