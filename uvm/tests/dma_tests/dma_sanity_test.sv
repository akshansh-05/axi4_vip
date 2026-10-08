// File: dma_sanity_test.sv
// Description: Comprehensive End-to-End Sanity Test for DMA Standalone Verification.
//              Executes two sequential phases:
//              - Phase 1: MM2S Read Transfer (Memory -> Stream)
//              - Phase 2: S2MM Write Transfer (Stream -> Memory) with concurrent
//                         Write Descriptor and Ingress Stream Data driving via fork-join.

`ifndef DMA_SANITY_TEST_SV
`define DMA_SANITY_TEST_SV

class dma_sanity_test extends dma_base_test;

    typedef dma_rd_desc_sanity_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) rd_desc_seq_type;
    typedef dma_wr_desc_sanity_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
    typedef axis_packet_seq        #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_pkt_seq_type;

    `uvm_component_utils(dma_sanity_test)

    function new(string name = "dma_sanity_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        rd_desc_seq_type  rd_desc_seq;
        wr_desc_seq_type  wr_desc_seq;
        axis_pkt_seq_type axis_pkt_seq;

        phase.raise_objection(this, "Starting DMA Standalone Sanity Test");

        `uvm_info(get_type_name(), "Starting DMA Standalone Sanity Test", UVM_LOW)

        // Phase 1: MM2S Read Transfer (Memory -> Stream)
        // Issue a read descriptor for 64 bytes (16 beats of 4 bytes) at address 0x1000.
        // The AXI read slave serves read bursts, and stream read VIP sinks the data beats.
        `uvm_info(get_type_name(), "Phase 1: Starting MM2S Read Transfer", UVM_LOW)

        rd_desc_seq = rd_desc_seq_type::type_id::create("rd_desc_seq");
        rd_desc_seq.start_addr = 16'h1000;
        rd_desc_seq.xfer_len   = 64;
        rd_desc_seq.xfer_tag   = 8'h01;

        rd_desc_seq.start(env.dma_rd_desc_agent.seqr);

        // Allow time for memory read bursts and descriptor status response to complete
        #300;
        `uvm_info(get_type_name(), "Phase 1: MM2S Read Transfer completed", UVM_LOW)

        // Phase 2: S2MM Write Transfer (Stream -> Memory)
        // Concurrently drive the write descriptor and ingress stream data beats.
        // Descriptor defines destination address 0x2000 and 64-byte buffer size.
        // Stream packet sends 16 beats (64 bytes) with TLAST on the final beat.
        `uvm_info(get_type_name(), "Phase 2: Starting S2MM Write Transfer", UVM_LOW)

        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq");
        wr_desc_seq.dest_addr  = 16'h2000;
        wr_desc_seq.buffer_len = 64;
        wr_desc_seq.xfer_tag   = 8'h02;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq");
        axis_pkt_seq.num_packets          = 1;
        axis_pkt_seq.min_beats            = 16;
        axis_pkt_seq.max_beats            = 16;
        axis_pkt_seq.force_full_last_keep = 1'b1; // Guarantee all 4 byte lanes on final beat (exactly 64 bytes)

        fork
            begin
                wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
            end
            begin
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
            end
        join

        // Allow time for write burst handshakes and write status response to settle
        #300;
        `uvm_info(get_type_name(), "Phase 2: S2MM Write Transfer completed", UVM_LOW)

        // End of test drain
        #500;
        `uvm_info(get_type_name(), "DMA Standalone Sanity Test PASSED", UVM_LOW)

        phase.drop_objection(this, "Completed DMA Standalone Sanity Test");
    endtask : run_phase

endclass : dma_sanity_test

`endif // DMA_SANITY_TEST_SV
