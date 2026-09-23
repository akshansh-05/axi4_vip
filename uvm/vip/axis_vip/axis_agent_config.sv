// File: axis_agent_config.sv
// Description: Configuration object for AXI4-Stream Agent controlling active/passive
//              operation mode, virtual interface handles, and timing knobs.

`ifndef AXIS_AGENT_CONFIG_SV
`define AXIS_AGENT_CONFIG_SV

class axis_agent_config #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_object;

    // Active (Driver + Monitor + Sequencer) or Passive (Monitor only)
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // Agent role indicator: 1 = Master (Producer), 0 = Slave (Consumer)
    bit is_master = 1'b1;

    // Virtual interface handle to axis_if
    virtual axis_if #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) vif;

    // Flow control knobs
    int unsigned default_ready_delay = 0; // Default wait cycles before asserting TREADY (slave mode)
    bit          ready_always_high   = 1'b1; // Hold TREADY high continuously (slave mode)

    `uvm_object_param_utils(axis_agent_config #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "axis_agent_config");
        super.new(name);
    endfunction : new

endclass : axis_agent_config

`endif // AXIS_AGENT_CONFIG_SV
