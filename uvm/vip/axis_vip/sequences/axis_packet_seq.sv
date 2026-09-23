// File: axis_packet_seq.sv
// Description: Configurable AXI4-Stream packet sequence. Generates one or more
//              stream packets with controllable beat count, data pattern, and
//              inter-beat delays. Supports both directed and randomized modes.

`ifndef AXIS_PACKET_SEQ_SV
`define AXIS_PACKET_SEQ_SV

class axis_packet_seq #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends axis_base_seq #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH);

    // Sequence configuration knobs
    int unsigned num_packets   = 1;       // Number of packets to generate
    int unsigned min_beats     = 1;       // Minimum beats per packet
    int unsigned max_beats     = 16;      // Maximum beats per packet
    bit          use_increment = 1'b0;    // Use incrementing data pattern instead of random

    `uvm_object_param_utils(axis_packet_seq #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "axis_packet_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type pkt;

        for (int p = 0; p < num_packets; p++) begin
            pkt = item_type::type_id::create($sformatf("axis_pkt_%0d", p));

            start_item(pkt);

            if (use_increment) begin
                // Directed: incrementing data pattern with zero delays
                assert(pkt.randomize() with {
                    data.size() inside {[min_beats:max_beats]};
                    foreach (delay[i]) delay[i] == 0;
                }) else `uvm_error(get_type_name(), "Randomization failed for axis_packet_seq")

                // Overwrite data with incrementing pattern
                foreach (pkt.data[i]) begin
                    pkt.data[i] = (p * max_beats + i) & {DATA_WIDTH{1'b1}};
                end
            end else begin
                // Fully randomized packet
                assert(pkt.randomize() with {
                    data.size() inside {[min_beats:max_beats]};
                }) else `uvm_error(get_type_name(), "Randomization failed for axis_packet_seq")
            end

            `uvm_info(get_type_name(), $sformatf("Sending packet [%0d/%0d]: %0d beats, ID=0x%0x",
                      p+1, num_packets, pkt.data.size(), pkt.id), UVM_MEDIUM)

            finish_item(pkt);
        end
    endtask : body

endclass : axis_packet_seq

`endif // AXIS_PACKET_SEQ_SV
