// File: dma_wr_partial_len_test.sv
// Description: Feature Test for S2MM_06: Non-Word-Multiple Transfer Length & Final WSTRB Mask.
//              Verifies partial transfer lengths where the final beat contains fewer
//              than 4 valid bytes, ensuring correct WSTRB deassertion on trailing byte lanes.

`ifndef DMA_WR_PARTIAL_LEN_TEST_SV
`define DMA_WR_PARTIAL_LEN_TEST_SV

class dma_wr_partial_len_test extends dma_base_test;

    typedef dma_wr_desc_partial_len_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
    typedef axis_packet_seq             #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_pkt_seq_type;

    `uvm_component_utils(dma_wr_partial_len_test)

    function new(string name = "dma_wr_partial_len_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        wr_desc_seq_type  wr_desc_seq;
        axis_pkt_seq_type axis_pkt_seq;

        phase.raise_objection(this, "Starting S2MM_06 Partial Length Write Test");

        `uvm_info(get_type_name(), "Starting S2MM_06 Partial Length Write Test (3 Sub-Iterations: 13B, 14B, 15B)", UVM_LOW)

        // Sub-iteration 1: buffer_len = 13B (rem = 1B, expected final WSTRB = 4'b0001, tag = 0x08)
        // Stream VIP drives 13 bytes across 4 beats: 3 full beats (12B) + 1 partial beat (1B, forced_last_keep = 4'b0001)
        // DMA DUT maps 13 bytes across 4 AXI beats (AWLEN = 3): Beats 0..2 WSTRB = 4'b1111, Beat 3 WSTRB = 4'b0001
        `uvm_info(get_type_name(), "Sub-iteration 1: dest_addr = 0x2000, buffer_len = 13B (rem=1B), tag = 0x08", UVM_LOW)
        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq_iter1");
        wr_desc_seq.dest_addr  = 16'h2000;
        wr_desc_seq.buffer_len = 13;
        wr_desc_seq.xfer_tag   = 8'h08;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter1");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 4;
        axis_pkt_seq.max_beats                = 4;
        axis_pkt_seq.forced_last_keep         = 4'b0001;
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

        // Sub-iteration 2: buffer_len = 14B (rem = 2B, expected final WSTRB = 4'b0011, tag = 0x09)
        // Stream VIP drives 14 bytes across 4 beats: 3 full beats (12B) + 1 partial beat (2B, forced_last_keep = 4'b0011)
        // DMA DUT maps 14 bytes across 4 AXI beats (AWLEN = 3): Beats 0..2 WSTRB = 4'b1111, Beat 3 WSTRB = 4'b0011
        `uvm_info(get_type_name(), "Sub-iteration 2: dest_addr = 0x2000, buffer_len = 14B (rem=2B), tag = 0x09", UVM_LOW)
        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq_iter2");
        wr_desc_seq.dest_addr  = 16'h2000;
        wr_desc_seq.buffer_len = 14;
        wr_desc_seq.xfer_tag   = 8'h09;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter2");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 4;
        axis_pkt_seq.max_beats                = 4;
        axis_pkt_seq.forced_last_keep         = 4'b0011;
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

        // Sub-iteration 3: buffer_len = 15B (rem = 3B, expected final WSTRB = 4'b0111, tag = 0x0A)
        // Stream VIP drives 15 bytes across 4 beats: 3 full beats (12B) + 1 partial beat (3B, forced_last_keep = 4'b0111)
        // DMA DUT maps 15 bytes across 4 AXI beats (AWLEN = 3): Beats 0..2 WSTRB = 4'b1111, Beat 3 WSTRB = 4'b0111
        `uvm_info(get_type_name(), "Sub-iteration 3: dest_addr = 0x2000, buffer_len = 15B (rem=3B), tag = 0x0A", UVM_LOW)
        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq_iter3");
        wr_desc_seq.dest_addr  = 16'h2000;
        wr_desc_seq.buffer_len = 15;
        wr_desc_seq.xfer_tag   = 8'h0A;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter3");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 4;
        axis_pkt_seq.max_beats                = 4;
        axis_pkt_seq.forced_last_keep         = 4'b0111;
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
        phase.drop_objection(this, "Completed S2MM_06 Partial Length Write Test");
    endtask : run_phase

endclass : dma_wr_partial_len_test

`endif // DMA_WR_PARTIAL_LEN_TEST_SV