// File: dma_rd_partial_len_test.sv
// Description: Feature Test for MM2S_05: Non-Word-Multiple Transfer Length & Final TKEEP Mask.
//              Executes 3 sequential sub-iterations testing partial transfer lengths:
//              - 13 Bytes (rem = 1B, expected final TKEEP = 4'b0001)
//              - 14 Bytes (rem = 2B, expected final TKEEP = 4'b0011)
//              - 15 Bytes (rem = 3B, expected final TKEEP = 4'b0111)

`ifndef DMA_RD_PARTIAL_LEN_TEST_SV
`define DMA_RD_PARTIAL_LEN_TEST_SV

class dma_rd_partial_len_test extends dma_base_test;

    typedef dma_rd_desc_partial_len_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) seq_type;

    `uvm_component_utils(dma_rd_partial_len_test)

    function new(string name = "dma_rd_partial_len_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        seq_type rd_seq;

        phase.raise_objection(this, "Starting MM2S_05 Partial-Length Test");

        `uvm_info(get_type_name(), "Starting MM2S_05 Partial-Length Read Test (13B, 14B, 15B)", UVM_LOW)

        // Sub-iteration 1: 13 Bytes (rem = 1B -> final TKEEP = 4'b0001, tag = 0x07)
        `uvm_info(get_type_name(), "Sub-iteration 1: Start Addr = 0x1000, Len = 13B (rem 1B), Tag = 0x07", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter1");
        rd_seq.start_addr = 16'h1000;
        rd_seq.xfer_len   = 13;
        rd_seq.xfer_tag   = 8'h07;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #400;

        // Sub-iteration 2: 14 Bytes (rem = 2B -> final TKEEP = 4'b0011, tag = 0x08)
        `uvm_info(get_type_name(), "Sub-iteration 2: Start Addr = 0x1000, Len = 14B (rem 2B), Tag = 0x08", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter2");
        rd_seq.start_addr = 16'h1000;
        rd_seq.xfer_len   = 14;
        rd_seq.xfer_tag   = 8'h08;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #400;

        // Sub-iteration 3: 15 Bytes (rem = 3B -> final TKEEP = 4'b0111, tag = 0x09)
        `uvm_info(get_type_name(), "Sub-iteration 3: Start Addr = 0x1000, Len = 15B (rem 3B), Tag = 0x09", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter3");
        rd_seq.start_addr = 16'h1000;
        rd_seq.xfer_len   = 15;
        rd_seq.xfer_tag   = 8'h09;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #400;

        #500;
        phase.drop_objection(this, "Completed MM2S_05 Partial-Length Test");
    endtask : run_phase

endclass : dma_rd_partial_len_test

`endif // DMA_RD_PARTIAL_LEN_TEST_SV
