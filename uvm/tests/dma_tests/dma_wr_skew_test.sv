// File: dma_wr_skew_test.sv
// Description: Feature Test for S2MM_10: Asynchronous Control-Data Timing Skew.
//              Verifies asynchronous timing skew between control descriptor and stream data:
//              - Sub-iteration 1 (Data-First): Stream data arrives before descriptor command;
//                DMA holds TREADY=0 and backpressures unallocated stream ingress.
//              - Sub-iteration 2 (Desc-First): Descriptor arrives before stream data;
//                DMA suppresses AXI AWVALID until stream data ingresses without deadlocks.

`ifndef DMA_WR_SKEW_TEST_SV
`define DMA_WR_SKEW_TEST_SV

class dma_wr_skew_test extends dma_base_test;

    typedef dma_wr_desc_skew_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
    typedef axis_packet_seq       #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_pkt_seq_type;

    `uvm_component_utils(dma_wr_skew_test)

    function new(string name = "dma_wr_skew_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        wr_desc_seq_type  wr_desc_seq;
        axis_pkt_seq_type axis_pkt_seq;

        phase.raise_objection(this, "Starting S2MM_10 Asynchronous Timing Skew Test");

        `uvm_info(get_type_name(), "Starting S2MM_10 Timing Skew Test (Sub-iter 1: Data-First, Sub-iter 2: Desc-First)", UVM_LOW)

        // Sub-iteration 1: Data-First Skew (Stream arrives first, Descriptor delayed by 10 cycles)
        `uvm_info(get_type_name(), "Executing Sub-iteration 1: Data-First Skew (Tag 0x0E)", UVM_LOW)
        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq_iter1");
        wr_desc_seq.dest_addr   = 16'h2000;
        wr_desc_seq.buffer_len  = 64;
        wr_desc_seq.xfer_tag    = 8'h0E;
        wr_desc_seq.issue_delay = 10; // Wait 10 cycles before asserting descriptor valid

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter1");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 16;
        axis_pkt_seq.max_beats                = 16;
        axis_pkt_seq.force_full_last_keep     = 1'b1;
        axis_pkt_seq.inter_packet_delay       = 0;
        axis_pkt_seq.inter_beat_delay         = 0;
        axis_pkt_seq.initial_delay            = 0;
        axis_pkt_seq.enable_random_beat_delay = 0;
        axis_pkt_seq.max_delay                = 0; // Injects immediately at wire speed

        fork
            begin
                wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
            end
            begin
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
            end
        join
        #400;

        // Sub-iteration 2: Desc-First Skew (Descriptor arrives first, Stream delayed by 10 cycles)
        `uvm_info(get_type_name(), "Executing Sub-iteration 2: Desc-First Skew (Tag 0x0F)", UVM_LOW)
        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq_iter2");
        wr_desc_seq.dest_addr   = 16'h3000;
        wr_desc_seq.buffer_len  = 64;
        wr_desc_seq.xfer_tag    = 8'h0F;
        wr_desc_seq.issue_delay = 0; // Issue descriptor immediately

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter2");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 16;
        axis_pkt_seq.max_beats                = 16;
        axis_pkt_seq.force_full_last_keep     = 1'b1;
        axis_pkt_seq.inter_packet_delay       = 0;
        axis_pkt_seq.inter_beat_delay         = 0;
        axis_pkt_seq.initial_delay            = 10; // 10 clock cycles bubble before asserting TVALID on beat 0
        axis_pkt_seq.enable_random_beat_delay = 0;
        axis_pkt_seq.max_delay                = 0;

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
        phase.drop_objection(this, "Completed S2MM_10 Asynchronous Timing Skew Test");
    endtask : run_phase

endclass : dma_wr_skew_test

`endif // DMA_WR_SKEW_TEST_SV
