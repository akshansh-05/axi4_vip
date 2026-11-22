// File: dma_wr_nominal_test.sv
// Description: Feature Test for S2MM_01: Nominal Aligned Single-Burst Write.
//              Verifies baseline single-burst stream-to-memory write transfer
//              (64 bytes / 16 beats) with word-aligned destination address (0x2000)
//              and full byte strobes (WSTRB = 4'b1111).

`ifndef DMA_WR_NOMINAL_TEST_SV
`define DMA_WR_NOMINAL_TEST_SV

class dma_wr_nominal_test extends dma_base_test;

    typedef dma_wr_desc_nominal_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
    typedef axis_packet_seq        #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_pkt_seq_type;

    `uvm_component_utils(dma_wr_nominal_test)

    function new(string name = "dma_wr_nominal_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        wr_desc_seq_type  wr_desc_seq;
        axis_pkt_seq_type axis_pkt_seq;

        phase.raise_objection(this, "Starting S2MM_01 Nominal Write Test");

        `uvm_info(get_type_name(), "Starting S2MM_01 Nominal Write Test (64 Bytes / 16 Beats)", UVM_LOW)

        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq");
        wr_desc_seq.dest_addr  = 16'h2000;
        wr_desc_seq.buffer_len = 64;
        wr_desc_seq.xfer_tag   = 8'h01;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq");
        axis_pkt_seq.num_packets          = 1;
        axis_pkt_seq.min_beats            = 16;
        axis_pkt_seq.max_beats            = 16;
        axis_pkt_seq.force_full_last_keep = 1'b1; // Guarantee 4'b1111 on final beat (exactly 64 bytes)
        axis_pkt_seq.max_delay            = 0;    // Wire-speed streaming

        fork
            begin
                wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
            end
            begin
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
            end
        join

        #300;
        `uvm_info(get_type_name(), "S2MM_01 Nominal Write transfer completed", UVM_LOW)

        #500;
        phase.drop_objection(this, "Completed S2MM_01 Nominal Write Test");
    endtask : run_phase

endclass : dma_wr_nominal_test

`endif // DMA_WR_NOMINAL_TEST_SV

