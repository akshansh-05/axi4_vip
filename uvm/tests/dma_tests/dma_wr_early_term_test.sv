// File: dma_wr_early_term_test.sv
// Description: Feature Test for S2MM_07: Early Stream Termination.
//              Verifies that when incoming stream asserts TLAST before descriptor length
//              is fulfilled, the DMA completes the in-flight AXI burst with WSTRB=4'b0000
//              dummy padding, issues new burst addresses only as needed by stream progress,
//              terminates cleanly, and reports actual received byte count.

`ifndef DMA_WR_EARLY_TERM_TEST_SV
`define DMA_WR_EARLY_TERM_TEST_SV

class dma_wr_early_term_test extends dma_base_test;

    typedef dma_wr_desc_early_term_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
    typedef axis_packet_seq            #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_pkt_seq_type;

    `uvm_component_utils(dma_wr_early_term_test)

    function new(string name = "dma_wr_early_term_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        wr_desc_seq_type  wr_desc_seq;
        axis_pkt_seq_type axis_pkt_seq;

        phase.raise_objection(this, "Starting S2MM_07 Early Stream Termination Test");

        `uvm_info(get_type_name(), "Starting S2MM_07 Early Stream Termination Test (2 Sub-Iterations)", UVM_LOW)

        // Sub-iteration 1: Mid-Burst Early Termination within Single Burst
        // Descriptor promises 64 bytes (1 burst of 16 beats, AWLEN=15 at 0x2000).
        // Stream VIP drives 32 bytes (8 beats) with TLAST on beat 7.
        // DMA writes beats 0..7 with WSTRB=4'b1111, then pads beats 8..15 with WSTRB=4'b0000.
        // Status reports actual transferred length = 32 bytes.
        `uvm_info(get_type_name(), "Sub-iteration 1: Mid-Burst Dummy Padding (Desc=64B, Stream=32B, Tag=0x0B)", UVM_LOW)
        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq_iter1");
        wr_desc_seq.dest_addr  = 16'h2000;
        wr_desc_seq.buffer_len = 64;
        wr_desc_seq.xfer_tag   = 8'h0B;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter1");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 8;  // 8 beats = 32 bytes
        axis_pkt_seq.max_beats                = 8;
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
        #500;

        // Sub-iteration 2: Multi-Burst Early Termination (20 Beats / 80 Bytes into 128B Descriptor)
        // Descriptor promises 128 bytes (up to two 64-byte bursts starting at 0x3000).
        // Stream VIP drives 20 beats (80 bytes) with TLAST asserted on beat 19:
        //   - Burst 1: AWADDR = 0x3000, AWLEN = 15. All 16 beats are valid (WSTRB = 4'b1111).
        //   - Burst 2: AWADDR = 0x3040, AWLEN = 15. Beats 0..3 are valid stream data (WSTRB = 4'b1111).
        //              Beats 4..15 (12 beats) are dummy padded with WSTRB = 4'b0000.
        // Status reports actual transferred length = 80 bytes.
        `uvm_info(get_type_name(), "Sub-iteration 2: Multi-Burst Crossing (Desc=128B, Stream=80B / 20 Beats, Tag=0x0C)", UVM_LOW)
        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq_iter2");
        wr_desc_seq.dest_addr  = 16'h3000;
        wr_desc_seq.buffer_len = 128; // Promised 128 bytes
        wr_desc_seq.xfer_tag   = 8'h0C;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter2");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 20; // 20 beats = 80 bytes (spills into Burst 2!)
        axis_pkt_seq.max_beats                = 20;
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
        #500;

        #500;
        phase.drop_objection(this, "Completed S2MM_07 Early Stream Termination Test");
    endtask : run_phase

endclass : dma_wr_early_term_test

`endif // DMA_WR_EARLY_TERM_TEST_SV