// File: axis_sequencer.sv
// Description: UVM Sequencer for AXI4-Stream transactions.

`ifndef AXIS_SEQUENCER_SV
`define AXIS_SEQUENCER_SV

class axis_sequencer #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequencer #(axis_seq_item #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    `uvm_component_param_utils(axis_sequencer #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "axis_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

endclass : axis_sequencer

`endif // AXIS_SEQUENCER_SV
