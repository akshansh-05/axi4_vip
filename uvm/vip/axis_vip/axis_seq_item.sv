// File: axis_seq_item.sv
// Description: UVM sequence item modeling AXI4-Stream packets and beats.
//              Supports dynamic multi-beat streaming transfers with byte-level
//              qualifiers (TKEEP), packet boundaries (TLAST), routing metadata
//              (TID, TDEST, TUSER), and configurable inter-beat delays.

`ifndef AXIS_SEQ_ITEM_SV
`define AXIS_SEQ_ITEM_SV

class axis_seq_item #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence_item;

    // Stream payload and byte enables
    // Dynamic arrays represent multi-beat packet transfers
    rand bit [DATA_WIDTH-1:0]  data[];   // Payload beats
    rand bit [KEEP_WIDTH-1:0]  keep[];   // Byte enables per beat

    // Stream sideband metadata
    rand bit [ID_WIDTH-1:0]    id;       // Stream source TID
    rand bit [DEST_WIDTH-1:0]  dest;     // Stream routing TDEST
    rand bit [USER_WIDTH-1:0]  user[];   // Sideband TUSER per beat

    // Handshake and flow control timing
    rand int unsigned          delay[];      // Master: Inter-beat delay cycles before asserting TVALID
    rand int unsigned          ready_delay;  // Slave: Cycles to deassert TREADY before asserting it

    // Constraints for legal AXI-Stream packets
    constraint c_payload_size {
        data.size() inside {[1:256]};
        keep.size() == data.size();
        user.size() == data.size();
        delay.size() == data.size();
    }

constraint c_keep_default {
    foreach (keep[i]) {
        if (i < data.size() - 1) {
            keep[i] == {KEEP_WIDTH{1'b1}}; // Standard: All middle beats are full 4'b1111
        } else {
            keep[i] != {KEEP_WIDTH{1'b0}}; // Standard: Last beat has at least 1 active byte
        }
    }
}

    constraint c_default_delays {
        foreach (delay[i]) {
            delay[i] inside {[0:5]};
        }
    }

    constraint c_ready_delay_default {
        soft ready_delay inside {[0:5]};
    }

    // UVM Field Automation Macros
    `uvm_object_param_utils_begin(axis_seq_item #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))
        `uvm_field_array_int(data,         UVM_ALL_ON | UVM_HEX)
        `uvm_field_array_int(keep,         UVM_ALL_ON | UVM_BIN)
        `uvm_field_int      (id,           UVM_ALL_ON)
        `uvm_field_int      (dest,         UVM_ALL_ON)
        `uvm_field_array_int(user,         UVM_ALL_ON)
        `uvm_field_array_int(delay,        UVM_ALL_ON | UVM_DEC)
        `uvm_field_int      (ready_delay,  UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "axis_seq_item");
        super.new(name);
    endfunction : new

endclass : axis_seq_item

`endif // AXIS_SEQ_ITEM_SV
