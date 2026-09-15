// File: dma_desc_sanity_test.sv
// Description: Sanity test executing both Read and Write descriptor driver sequences
//              to verify that descriptor signals are driven and accepted by the DMA DUT.

`ifndef DMA_DESC_SANITY_TEST_SV
`define DMA_DESC_SANITY_TEST_SV

class dma_desc_sanity_test extends dma_base_test;

    typedef dma_rd_desc_sanity_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) rd_desc_seq_type;
    typedef dma_wr_desc_sanity_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;

    `uvm_component_utils(dma_desc_sanity_test)

    function new(string name = "dma_desc_sanity_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        rd_desc_seq_type rd_seq;
        wr_desc_seq_type wr_seq;

        rd_seq = rd_desc_seq_type::type_id::create("rd_seq");
        wr_seq = wr_desc_seq_type::type_id::create("wr_seq");

        phase.raise_objection(this, "Starting DMA Descriptor Sanity Test");
        `uvm_info("DESC_SANITY", "Executing Read and Write Descriptor handshakes...", UVM_LOW)

        // 1. Launch Read Descriptor Sequence on Read Descriptor Sequencer
        `uvm_info("DESC_SANITY", "Launching Read Descriptor sequence...", UVM_MEDIUM)
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        `uvm_info("DESC_SANITY", "Read Descriptor accepted by DUT!", UVM_MEDIUM)

        // 2. Launch Write Descriptor Sequence on Write Descriptor Sequencer
        `uvm_info("DESC_SANITY", "Launching Write Descriptor sequence...", UVM_MEDIUM)
        wr_seq.start(env.dma_wr_desc_agent.seqr);
        `uvm_info("DESC_SANITY", "Write Descriptor accepted by DUT!", UVM_MEDIUM)

        #100; // Small drain time to observe post-handshake bus state in waves
        `uvm_info("DESC_SANITY", "Descriptor Sanity Test Completed Successfully!", UVM_LOW)
        phase.drop_objection(this, "Completed DMA Descriptor Sanity Test");
    endtask : run_phase

endclass : dma_desc_sanity_test

`endif // DMA_DESC_SANITY_TEST_SV
