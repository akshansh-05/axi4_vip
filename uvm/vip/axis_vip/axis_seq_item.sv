// File: axis_seq_item.sv
// Description: Sequence item modeling an AXI4-Stream packet (all beats from
//              start to tlast) for the AXI4 DMA subsystem.

`ifndef AXIS_SEQ_ITEM_SV
`define AXIS_SEQ_ITEM_SV

class axis_seq_item #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence_item;

    // Stream Packet Payload (one entry per beat)
    rand bit [DATA_WIDTH-1:0] data[];
    rand bit [KEEP_WIDTH-1:0] keep[];

    // Packet-level metadata (constant across all beats of a packet)
    rand bit [ID_WIDTH-1:0]   id;
    rand bit [DEST_WIDTH-1:0] dest;
    rand bit [USER_WIDTH-1:0] user;

    // Stimulus pacing (inter-beat delay cycles)
    rand int unsigned         valid_delay;

    // UVM Field Macros
    `uvm_object_param_utils_begin(axis_seq_item #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))
        `uvm_field_array_int(data,        UVM_ALL_ON | UVM_HEX)
        `uvm_field_array_int(keep,        UVM_ALL_ON | UVM_HEX)
        `uvm_field_int      (id,          UVM_ALL_ON | UVM_HEX)
        `uvm_field_int      (dest,        UVM_ALL_ON | UVM_HEX)
        `uvm_field_int      (user,        UVM_ALL_ON | UVM_BIN)
        `uvm_field_int      (valid_delay, UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    // Constraints
    constraint c_packet_length {
        data.size() > 0;
        keep.size() == data.size();
        soft data.size() inside {[1:16]};
    }

    constraint c_keep_valid {
        foreach (keep[i]) {
            if (i < keep.size() - 1) {
                keep[i] == {KEEP_WIDTH{1'b1}};
            } else {
                keep[i] != '0; // At least one byte active in the last beat
            }
        }
    }

    constraint c_metadata_defaults {
        soft id   == '0;
        soft dest == '0;
        soft user == '0;
    }

    constraint c_delay_range {
        soft valid_delay inside {[0:3]};
    }

    function new(string name = "axis_seq_item");
        super.new(name);
    endfunction : new

    // Helper: calculate total bytes in this packet based on keep bits
    virtual function int unsigned get_byte_count();
        int unsigned total = 0;
        foreach (keep[i]) begin
            for (int b = 0; b < KEEP_WIDTH; b++) begin
                if (keep[i][b]) total++;
            end
        end
        return total;
    endfunction : get_byte_count

    virtual function string convert2string();
        string s;
        s = $sformatf("AXIS Packet: beats=%0d, total_bytes=%0d, id=0x%0x, dest=0x%0x, user=0x%0x\n",
                      data.size(), get_byte_count(), id, dest, user);
        foreach (data[i]) begin
            s = {s, $sformatf("  Beat[%02d]: data=0x%08x, keep=0x%01x%s\n",
                              i, data[i], keep[i], (i == data.size()-1) ? " [LAST]" : "")};
        end
        return s;
    endfunction : convert2string

endclass : axis_seq_item

`endif // AXIS_SEQ_ITEM_SV
