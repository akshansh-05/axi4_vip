// File: dma_rd_4kb_split_test.sv
// Description: Feature Test for MM2S_03: 4KB Boundary Crossing Read Split.
//              Verifies that a 64-byte descriptor transfer crossing a 4KB
//              boundary at 0x1000 is legally clamped and split into two
//              8-beat sub-bursts (0x0FE0 and 0x1000).

`ifndef DMA_RD_4KB_SPLIT_TEST_SV
`define DMA_RD_4KB_SPLIT_TEST_SV

class dma_rd_4kb_split_test extends dma_base_test;

    typedef dma_rd_desc_4kb_split_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) seq_type;

    `uvm_component_utils(dma_rd_4kb_split_test)

    function new(string name = "dma_rd_4kb_split_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        seq_type rd_seq;

        phase.raise_objection(this, "Starting MM2S_03 4KB Split Test");

        `uvm_info(get_type_name(), "Starting MM2S_03 4KB Split Test (64 Bytes across 4KB boundary at 0x1000)", UVM_LOW)

        rd_seq = seq_type::type_id::create("rd_seq");
        rd_seq.start_addr = 16'h0FE0;
        rd_seq.xfer_len   = 64;
        rd_seq.xfer_tag   = 8'h03;

        rd_seq.start(env.dma_rd_desc_agent.seqr);

        #600;
        `uvm_info(get_type_name(), "MM2S_03 4KB Split transfer completed", UVM_LOW)

        #500;
        phase.drop_objection(this, "Completed MM2S_03 4KB Split Test");
    endtask : run_phase

endclass : dma_rd_4kb_split_test

`endif // DMA_RD_4KB_SPLIT_TEST_SV
