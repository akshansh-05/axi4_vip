// File: dma_rd_nominal_test.sv
// Description: Feature Test for MM2S_01: Nominal Aligned Single-Burst Read.
//              Verifies baseline single-burst read operation (64 bytes / 16 beats)
//              with word-aligned start address and full byte enables.

`ifndef DMA_RD_NOMINAL_TEST_SV
`define DMA_RD_NOMINAL_TEST_SV

class dma_rd_nominal_test extends dma_base_test;

    typedef dma_rd_desc_nominal_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) seq_type;

    `uvm_component_utils(dma_rd_nominal_test)

    function new(string name = "dma_rd_nominal_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        seq_type rd_seq;

        phase.raise_objection(this, "Starting MM2S_01 Nominal Read Test");

        `uvm_info(get_type_name(), "Starting MM2S_01 Nominal Read Test (64 Bytes)", UVM_LOW)

        rd_seq = seq_type::type_id::create("rd_seq");
        rd_seq.start_addr = 16'h1000;
        rd_seq.xfer_len   = 64;
        rd_seq.xfer_tag   = 8'h01;

        rd_seq.start(env.dma_rd_desc_agent.seqr);

        #300;
        `uvm_info(get_type_name(), "MM2S_01 Nominal Read transfer completed", UVM_LOW)

        #500;
        phase.drop_objection(this, "Completed MM2S_01 Nominal Read Test");
    endtask : run_phase

endclass : dma_rd_nominal_test

`endif // DMA_RD_NOMINAL_TEST_SV