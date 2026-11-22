// File: dma_wr_b2b_test.sv
// Description: Feature Test for S2MM_02: Back-to-Back (B2B) Pipelined Descriptor Writes.
//              Verifies that the DMA write engine accepts back-to-back descriptors
//              without bubbles, manages status tracking FIFO credits correctly, and
//              successfully streams and writes both packets without data corruption.

`ifndef DMA_WR_B2B_TEST_SV
`define DMA_WR_B2B_TEST_SV

class dma_wr_b2b_test extends dma_base_test;

    typedef dma_wr_desc_b2b_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_b2b_seq_type;
    typedef axis_packet_seq     #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_pkt_seq_type;

    `uvm_component_utils(dma_wr_b2b_test)

    function new(string name = "dma_wr_b2b_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        wr_desc_b2b_seq_type wr_b2b_seq;
        axis_pkt_seq_type    axis_pkt_seq;

        phase.raise_objection(this, "Starting S2MM_02 Back-to-Back Write Test");

        `uvm_info(get_type_name(), "Starting S2MM_02 Back-to-Back Pipelined Descriptor Write Test (2 x 64B)", UVM_LOW)

        wr_b2b_seq = wr_desc_b2b_seq_type::type_id::create("wr_b2b_seq");
        wr_b2b_seq.dest_addr1  = 16'h2000;
        wr_b2b_seq.buffer_len1 = 64;
        wr_b2b_seq.xfer_tag1   = 8'h01;

        wr_b2b_seq.dest_addr2       = 16'h3000;
        wr_b2b_seq.buffer_len2      = 64;
        wr_b2b_seq.xfer_tag2        = 8'h02;
        wr_b2b_seq.inter_desc_delay = 0; // Wire-speed back-to-back descriptor issuance (0-cycle bubble)

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq");
        axis_pkt_seq.num_packets          = 2;
        axis_pkt_seq.min_beats            = 16;
        axis_pkt_seq.max_beats            = 16;
        axis_pkt_seq.force_full_last_keep = 1'b1; // Exactly 64 bytes per packet
        axis_pkt_seq.inter_packet_delay   = 0;    // Wire-speed streaming across packet boundaries (0-cycle gap)
        axis_pkt_seq.inter_beat_delay     = 0;    // Seamless streaming between beats (0-cycle gap)

        fork
            begin
                wr_b2b_seq.start(env.dma_wr_desc_agent.seqr);
            end
            begin
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
            end
        join

        #500;
        `uvm_info(get_type_name(), "S2MM_02 Back-to-Back Write transfers completed", UVM_LOW)

        #500;
        phase.drop_objection(this, "Completed S2MM_02 Back-to-Back Write Test");
    endtask : run_phase

endclass : dma_wr_b2b_test

`endif // DMA_WR_B2B_TEST_SV
