// File: dma_wr_stream_bubble_test.sv
// Description: Feature Test for S2MM Stage 1: Ingress AXI-Stream Delay & Bubble Assertion.
//              Verifies that the DMA write engine handles ingress stream starvation and
//              frame boundary pauses without writing false data or hanging:
//              - Sub-iteration 1: Single packet with pure inter-beat delay (Tag 0x10).
//              - Sub-iteration 2: Multi-packet transfer with both inter-beat delay
//                and inter-packet gap across 2 packets (Tags 0x11, 0x12).

`ifndef DMA_WR_STREAM_BUBBLE_TEST_SV
`define DMA_WR_STREAM_BUBBLE_TEST_SV

class dma_wr_stream_bubble_test extends dma_base_test;

    typedef dma_wr_desc_nominal_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_nom_seq_type;
    typedef dma_wr_desc_b2b_seq     #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_b2b_seq_type;
    typedef axis_packet_seq         #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_pkt_seq_type;

    `uvm_component_utils(dma_wr_stream_bubble_test)

    function new(string name = "dma_wr_stream_bubble_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        wr_desc_nom_seq_type wr_desc_nom_seq;
        wr_desc_b2b_seq_type wr_desc_b2b_seq;
        axis_pkt_seq_type    axis_pkt_seq;

        phase.raise_objection(this, "Starting S2MM Ingress Stream Bubble Test");

        `uvm_info(get_type_name(), "Starting S2MM Stream Bubble Test (Sub-iter 1: Inter-beat delay, Sub-iter 2: Inter-beat + Inter-packet delay)", UVM_LOW)

        // Sub-iteration 1: Single Packet with Pure Inter-Beat Delays (Tag 0x10)
        `uvm_info(get_type_name(), "Executing Sub-iteration 1: Single Packet Inter-Beat Delays (Tag 0x10)", UVM_LOW)
        wr_desc_nom_seq = wr_desc_nom_seq_type::type_id::create("wr_desc_nom_seq");
        wr_desc_nom_seq.dest_addr  = 16'h2000;
        wr_desc_nom_seq.buffer_len = 64; // 16 beats = 64 bytes
        wr_desc_nom_seq.xfer_tag   = 8'h10;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter1");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 16;
        axis_pkt_seq.max_beats                = 16;
        axis_pkt_seq.force_full_last_keep     = 1'b1;
        axis_pkt_seq.inter_packet_delay       = 0;
        axis_pkt_seq.inter_beat_delay         = 3; // Up to 3 bubble cycles between beats
        axis_pkt_seq.initial_delay            = 0;
        axis_pkt_seq.enable_random_beat_delay = 1; // Randomized beat jitter
        axis_pkt_seq.max_delay                = 0;

        fork
            begin
                wr_desc_nom_seq.start(env.dma_wr_desc_agent.seqr);
            end
            begin
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
            end
        join
        #400;

        // Sub-iteration 2: Multi-Packet Transfer with Inter-Beat AND Inter-Packet Delays (Tags 0x11, 0x12)
        `uvm_info(get_type_name(), "Executing Sub-iteration 2: Multi-Packet with Inter-Beat & Inter-Packet Delays (Tags 0x11, 0x12)", UVM_LOW)
        wr_desc_b2b_seq = wr_desc_b2b_seq_type::type_id::create("wr_desc_b2b_seq");
        wr_desc_b2b_seq.dest_addr1       = 16'h2040;
        wr_desc_b2b_seq.buffer_len1      = 64;
        wr_desc_b2b_seq.xfer_tag1        = 8'h11;
        wr_desc_b2b_seq.dest_addr2       = 16'h2080;
        wr_desc_b2b_seq.buffer_len2      = 64;
        wr_desc_b2b_seq.xfer_tag2        = 8'h12;
        wr_desc_b2b_seq.inter_desc_delay = 0; // Pipelined descriptor queueing

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter2");
        axis_pkt_seq.num_packets              = 2; // 2 distinct stream packets
        axis_pkt_seq.min_beats                = 16;
        axis_pkt_seq.max_beats                = 16;
        axis_pkt_seq.force_full_last_keep     = 1'b1;
        axis_pkt_seq.inter_packet_delay       = 8; // 8-cycle idle gap with TVALID=0 between packets
        axis_pkt_seq.inter_beat_delay         = 3; // Up to 3 bubble cycles between beats
        axis_pkt_seq.initial_delay            = 0;
        axis_pkt_seq.enable_random_beat_delay = 1;
        axis_pkt_seq.max_delay                = 0;

        fork
            begin
                wr_desc_b2b_seq.start(env.dma_wr_desc_agent.seqr);
            end
            begin
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
            end
        join
        #600;

        #500;
        phase.drop_objection(this, "Completed S2MM Ingress Stream Bubble Test");
    endtask : run_phase

endclass : dma_wr_stream_bubble_test

`endif // DMA_WR_STREAM_BUBBLE_TEST_SV
