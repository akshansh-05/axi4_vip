// File: axis_packet_seq.sv
// Description: Configurable AXI4-Stream packet sequence. Generates one or more
//              stream packets with controllable beat count and inter-beat delays.

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
    int unsigned         num_packets              = 1;       // Number of packets to generate
    int unsigned         min_beats                = 1;       // Minimum beats per packet
    int unsigned         max_beats                = 16;      // Maximum beats per packet
    bit                  force_full_last_keep     = 0;       // Force last beat TKEEP to all 1s (full word)
    bit [KEEP_WIDTH-1:0] forced_last_keep         = '0;      // Explicit TKEEP pattern for final beat (e.g. 4'b0001, 4'b0011, 4'b0111)

    // Handshake timing knobs:
    // inter_packet_delay: idle bubble cycles (TVALID low) inserted between successive packets (default: 0 for seamless wire-speed streaming)
    // inter_beat_delay:   idle bubble cycles (TVALID low) inserted between consecutive beats within a packet (default: 0 for back-to-back streaming)
    // initial_delay:      idle bubble cycles before the first beat of packet 0 (default: 0)
    // enable_random_beat_delay: if 1, delay varies randomly within [0:inter_beat_delay]; if 0, exact deterministic delay
    int unsigned         inter_packet_delay       = 0;
    int unsigned         inter_beat_delay         = 0;
    int unsigned         initial_delay            = 0;
    bit                  enable_random_beat_delay = 0;
    int unsigned         max_delay                = 0;       // Backward compatibility knob: sets inter-beat delay upper bound if non-zero

    `uvm_object_param_utils(axis_packet_seq #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "axis_packet_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type pkt;
        int unsigned cur_pkt_delay;
        int unsigned cur_beat_delay;

        // Backward compatibility: if max_delay was set and inter_beat_delay left at 0, honor max_delay
        cur_beat_delay = (max_delay > 0 && inter_beat_delay == 0) ? max_delay : inter_beat_delay;

        for (int p = 0; p < num_packets; p++) begin
            pkt = item_type::type_id::create($sformatf("axis_pkt_%0d", p));

            // Select delay before beat 0:
            // Packet 0 uses initial_delay (default 0).
            // Packets p > 0 use inter_packet_delay (default 0 for zero-cycle gap).
            cur_pkt_delay = (p == 0) ? initial_delay : inter_packet_delay;

            start_item(pkt);

            if (forced_last_keep != '0) begin
                assert(pkt.randomize() with {
                    // Packet length constrained within specified beat bounds
                    data.size() inside {[min_beats:max_beats]};

                    // Delay before beat 0 sets inter-packet bubble cycles
                    delay[0] == local::cur_pkt_delay;

                    // Delays for beats i > 0 set inter-beat bubble cycles
                    foreach (delay[i]) {
                        if (i > 0) {
                            if (local::enable_random_beat_delay) {
                                delay[i] inside {[0:local::cur_beat_delay]};
                            } else {
                                delay[i] == local::cur_beat_delay;
                            }
                        }
                    }

                    // Force explicit partial TKEEP byte qualifier on the final beat
                    keep[data.size() - 1] == local::forced_last_keep;
                }) else `uvm_error(get_type_name(), "Randomization failed for axis_packet_seq");
            end else if (force_full_last_keep) begin
                assert(pkt.randomize() with {
                    // Packet length constrained within specified beat bounds
                    data.size() inside {[min_beats:max_beats]};

                    // Delay before beat 0 sets inter-packet bubble cycles
                    delay[0] == local::cur_pkt_delay;

                    // Delays for beats i > 0 set inter-beat bubble cycles
                    foreach (delay[i]) {
                        if (i > 0) {
                            if (local::enable_random_beat_delay) {
                                delay[i] inside {[0:local::cur_beat_delay]};
                            } else {
                                delay[i] == local::cur_beat_delay;
                            }
                        }
                    }

                    // Force all byte lanes active across all beats including the final beat
                    foreach (keep[i]) {
                        keep[i] == {KEEP_WIDTH{1'b1}};
                    }
                }) else `uvm_error(get_type_name(), "Randomization failed for axis_packet_seq");
            end else begin
                assert(pkt.randomize() with {
                    // Packet length constrained within specified beat bounds
                    data.size() inside {[min_beats:max_beats]};

                    // Delay before beat 0 sets inter-packet bubble cycles
                    delay[0] == local::cur_pkt_delay;

                    // Delays for beats i > 0 set inter-beat bubble cycles
                    foreach (delay[i]) {
                        if (i > 0) {
                            if (local::enable_random_beat_delay) {
                                delay[i] inside {[0:local::cur_beat_delay]};
                            } else {
                                delay[i] == local::cur_beat_delay;
                            }
                        }
                    }
                }) else `uvm_error(get_type_name(), "Randomization failed for axis_packet_seq");
            end

            `uvm_info(get_type_name(), $sformatf("Sending packet [%0d/%0d]:\n%s",
                      p+1, num_packets, pkt.sprint()), UVM_MEDIUM)

            finish_item(pkt);
        end
    endtask : body

endclass : axis_packet_seq

`endif // AXIS_PACKET_SEQ_SV
