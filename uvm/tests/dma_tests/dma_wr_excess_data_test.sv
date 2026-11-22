// File: dma_wr_excess_data_test.sv
// Description: Feature Test for S2MM_08: Excess Stream Data Ingress.
//              Verifies that when incoming stream data exceeds descriptor buffer length,
//              the DMA completes the memory write up to buffer_len, enters STATE_DROP_DATA,
//              maintains TREADY=1 to drain excess beats until TLAST, and prevents memory corruption.

`ifndef DMA_WR_EXCESS_DATA_TEST_SV
`define DMA_WR_EXCESS_DATA_TEST_SV

class dma_wr_excess_data_test extends dma_base_test;

    typedef dma_wr_desc_excess_data_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
    typedef axis_packet_seq             #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_pkt_seq_type;

    `uvm_component_utils(dma_wr_excess_data_test)

    function new(string name = "dma_wr_excess_data_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        wr_desc_seq_type  wr_desc_seq;
        axis_pkt_seq_type axis_pkt_seq;

        phase.raise_objection(this, "Starting S2MM_08 Excess Stream Data Test");

        `uvm_info(get_type_name(), "Starting S2MM_08 Excess Stream Data Test (Desc=32B, Stream=96B / 24 Beats)", UVM_LOW)

        // Descriptor allocates 32 bytes (8 beats at 0x2000, tag = 0x0D)
        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq");
        wr_desc_seq.dest_addr  = 16'h2000;
        wr_desc_seq.buffer_len = 32;
        wr_desc_seq.xfer_tag   = 8'h0D;

        // Stream VIP drives 24 beats (96 bytes):
        // Beats 0..7 (32B) are written to memory with WSTRB=4'b1111 (AWLEN=7).
        // Beats 8..23 (64B excess) are absorbed in STATE_DROP_DATA with TREADY=1.
        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 24;
        axis_pkt_seq.max_beats                = 24;
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

        #600;
        `uvm_info(get_type_name(), "S2MM_08 Excess Stream Data Write transfer completed", UVM_LOW)

        #500;
        phase.drop_objection(this, "Completed S2MM_08 Excess Stream Data Test");
    endtask : run_phase

endclass : dma_wr_excess_data_test

`endif // DMA_WR_EXCESS_DATA_TEST_SV