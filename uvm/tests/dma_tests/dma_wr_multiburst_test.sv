// File: dma_wr_multiburst_test.sv
// Description: Feature Test for S2MM_03: Multi-Burst Slicing Write (>16 Beats).
//              Verifies that write packets larger than AXI_MAX_BURST_LEN (64 bytes)
//              are automatically partitioned into consecutive 16-beat AXI bursts
//              (AWLEN=15) with correctly incrementing AWADDR.

`ifndef DMA_WR_MULTIBURST_TEST_SV
`define DMA_WR_MULTIBURST_TEST_SV

class dma_wr_multiburst_test extends dma_base_test;

    typedef dma_wr_desc_multiburst_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
    typedef axis_packet_seq            #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_pkt_seq_type;

    `uvm_component_utils(dma_wr_multiburst_test)

    function new(string name = "dma_wr_multiburst_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        wr_desc_seq_type  wr_desc_seq;
        axis_pkt_seq_type axis_pkt_seq;

        phase.raise_objection(this, "Starting S2MM_03 Multi-Burst Write Test");

        `uvm_info(get_type_name(), "Starting S2MM_03 Multi-Burst Write Test (256 Bytes / 64 Beats -> 4 Bursts)", UVM_LOW)

        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq");
        wr_desc_seq.dest_addr  = 16'h2000;
        wr_desc_seq.buffer_len = 256;
        wr_desc_seq.xfer_tag   = 8'h03;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq");
        axis_pkt_seq.num_packets          = 1;
        axis_pkt_seq.min_beats            = 64;   // 64 beats x 4 bytes = 256 bytes
        axis_pkt_seq.max_beats            = 64;
        axis_pkt_seq.force_full_last_keep = 1'b1; // Guarantee 4'b1111 on final beat
        axis_pkt_seq.inter_packet_delay   = 0;    // Wire-speed streaming across packets
        axis_pkt_seq.inter_beat_delay     = 0;    // Wire-speed continuous streaming across all 64 beats

        fork
            begin
                wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
            end
            begin
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
            end
        join

        #800;
        `uvm_info(get_type_name(), "S2MM_03 Multi-Burst Write transfer completed", UVM_LOW)

        #500;
        phase.drop_objection(this, "Completed S2MM_03 Multi-Burst Write Test");
    endtask : run_phase

endclass : dma_wr_multiburst_test

`endif // DMA_WR_MULTIBURST_TEST_SV
