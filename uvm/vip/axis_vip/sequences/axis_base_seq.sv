// File: axis_base_seq.sv
// Description: Base sequence for AXI4-Stream VIP. Provides common handles
//              and utility methods for derived stream sequences.

`ifndef AXIS_BASE_SEQ_SV
`define AXIS_BASE_SEQ_SV

class axis_base_seq #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(axis_seq_item #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef axis_seq_item #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(axis_base_seq #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "axis_base_seq");
        super.new(name);
    endfunction : new

endclass : axis_base_seq

`endif // AXIS_BASE_SEQ_SV
