// File: dma_wr_unaligned_test.sv
// Description: Feature Test for S2MM_05: Unaligned Destination Address & WSTRB Lane Offsets.
//              Verifies that unaligned write destination addresses (+1, +2, +3 bytes)
//              with a uniform word-multiple length (16 bytes) are correctly handled:
//              stream ingress contains only full words (TKEEP = 4'b1111), while the DMA RTL
//              barrel shifter aligns stream byte 0 to the target lane, deasserts initial WSTRB
//              on preceding lanes, and flushes residual bytes across the trailing beat.

`ifndef DMA_WR_UNALIGNED_TEST_SV
`define DMA_WR_UNALIGNED_TEST_SV

class dma_wr_unaligned_test extends dma_base_test;

    typedef dma_wr_desc_unaligned_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
    typedef axis_packet_seq           #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_pkt_seq_type;

    `uvm_component_utils(dma_wr_unaligned_test)

    function new(string name = "dma_wr_unaligned_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        wr_desc_seq_type  wr_desc_seq;
        axis_pkt_seq_type axis_pkt_seq;

        phase.raise_objection(this, "Starting S2MM_05 Unaligned Write Test");

        `uvm_info(get_type_name(), "Starting S2MM_05 Unaligned Write Test (3 Sub-Iterations: +1B, +2B, +3B with uniform 16B length)", UVM_LOW)

        // Sub-iteration 1: Offset +1 Byte (dest_addr = 0x2001, len = 16B, tag = 0x05)
        // Stream VIP drives 16 bytes across 4 full beats (TKEEP = 4'b1111 on all beats).
        // DMA DUT maps 16 bytes starting at 0x2001 across 5 AXI beats (AWLEN = 4):
        //   Beat 0 (0x2000): 3 bytes (lanes 1, 2, 3 active) -> WSTRB = 4'b1110 (lane 0 masked)
        //   Beats 1..3:      4 bytes each                   -> WSTRB = 4'b1111
        //   Beat 4 (0x2010): 1 byte (lane 0 active)         -> WSTRB = 4'b0001 (lanes 1..3 masked)
        `uvm_info(get_type_name(), "Sub-iteration 1: dest_addr = 0x2001 (+1B), len = 16B, tag = 0x05", UVM_LOW)
        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq_iter1");
        wr_desc_seq.dest_addr  = 16'h2001;
        wr_desc_seq.buffer_len = 16;
        wr_desc_seq.xfer_tag   = 8'h05;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter1");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 4;
        axis_pkt_seq.max_beats                = 4;
        axis_pkt_seq.forced_last_keep         = 4'b1111;
        axis_pkt_seq.force_full_last_keep     = 1;
        axis_pkt_seq.max_delay                = 0;
        axis_pkt_seq.inter_packet_delay       = 0;
        axis_pkt_seq.inter_beat_delay         = 0;
        axis_pkt_seq.initial_delay            = 0;
        axis_pkt_seq.enable_random_beat_delay = 0;

        fork
            begin
                wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
            end
            begin
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
            end
        join
        #400;

        // Sub-iteration 2: Offset +2 Bytes (dest_addr = 0x2002, len = 16B, tag = 0x06)
        // Stream VIP drives 16 bytes across 4 full beats (TKEEP = 4'b1111 on all beats).
        // DMA DUT maps 16 bytes starting at 0x2002 across 5 AXI beats (AWLEN = 4):
        //   Beat 0 (0x2000): 2 bytes (lanes 2, 3 active)    -> WSTRB = 4'b1100 (lanes 0, 1 masked)
        //   Beats 1..3:      4 bytes each                   -> WSTRB = 4'b1111
        //   Beat 4 (0x2010): 2 bytes (lanes 0, 1 active)    -> WSTRB = 4'b0011 (lanes 2, 3 masked)
        `uvm_info(get_type_name(), "Sub-iteration 2: dest_addr = 0x2002 (+2B), len = 16B, tag = 0x06", UVM_LOW)
        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq_iter2");
        wr_desc_seq.dest_addr  = 16'h2002;
        wr_desc_seq.buffer_len = 16;
        wr_desc_seq.xfer_tag   = 8'h06;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter2");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 4;
        axis_pkt_seq.max_beats                = 4;
        axis_pkt_seq.forced_last_keep         = 4'b1111;
        axis_pkt_seq.force_full_last_keep     = 1;
        axis_pkt_seq.max_delay                = 0;
        axis_pkt_seq.inter_packet_delay       = 0;
        axis_pkt_seq.inter_beat_delay         = 0;
        axis_pkt_seq.initial_delay            = 0;
        axis_pkt_seq.enable_random_beat_delay = 0;

        fork
            begin
                wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
            end
            begin
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
            end
        join
        #400;

        // Sub-iteration 3: Offset +3 Bytes (dest_addr = 0x2003, len = 16B, tag = 0x07)
        // Stream VIP drives 16 bytes across 4 full beats (TKEEP = 4'b1111 on all beats).
        // DMA DUT maps 16 bytes starting at 0x2003 across 5 AXI beats (AWLEN = 4):
        //   Beat 0 (0x2000): 1 byte (lane 3 active)         -> WSTRB = 4'b1000 (lanes 0..2 masked)
        //   Beats 1..3:      4 bytes each                   -> WSTRB = 4'b1111
        //   Beat 4 (0x2010): 3 bytes (lanes 0, 1, 2 active) -> WSTRB = 4'b0111 (lane 3 masked)
        `uvm_info(get_type_name(), "Sub-iteration 3: dest_addr = 0x2003 (+3B), len = 16B, tag = 0x07", UVM_LOW)
        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq_iter3");
        wr_desc_seq.dest_addr  = 16'h2003;
        wr_desc_seq.buffer_len = 16;
        wr_desc_seq.xfer_tag   = 8'h07;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter3");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 4;
        axis_pkt_seq.max_beats                = 4;
        axis_pkt_seq.forced_last_keep         = 4'b1111;
        axis_pkt_seq.force_full_last_keep     = 1;
        axis_pkt_seq.max_delay                = 0;
        axis_pkt_seq.inter_packet_delay       = 0;
        axis_pkt_seq.inter_beat_delay         = 0;
        axis_pkt_seq.initial_delay            = 0;
        axis_pkt_seq.enable_random_beat_delay = 0;

        fork
            begin
                wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
            end
            begin
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
            end
        join
        #400;

        #500;
        phase.drop_objection(this, "Completed S2MM_05 Unaligned Write Test");
    endtask : run_phase

endclass : dma_wr_unaligned_test

`endif // DMA_WR_UNALIGNED_TEST_SV