// File: dma_rd_unaligned_test.sv
// Description: Feature Test for MM2S_04: Unaligned Start Address & TKEEP Lane Offsets.
//              Executes 3 sequential sub-iterations testing start address offsets
//              +1B (0x1001), +2B (0x1002), and +3B (0x1003) to verify barrel-shifter
//              alignment to stream lane 0 and trailing TKEEP masking.

`ifndef DMA_RD_UNALIGNED_TEST_SV
`define DMA_RD_UNALIGNED_TEST_SV

class dma_rd_unaligned_test extends dma_base_test;

    typedef dma_rd_desc_unaligned_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) seq_type;

    `uvm_component_utils(dma_rd_unaligned_test)

    function new(string name = "dma_rd_unaligned_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        seq_type rd_seq;

        phase.raise_objection(this, "Starting MM2S_04 Unaligned Test");

        `uvm_info(get_type_name(), "Starting MM2S_04 Unaligned Read Test (3 Sub-Iterations)", UVM_LOW)

        // Sub-iteration 1: Offset +1 Byte (start_addr = 0x1001, len = 15, tag = 0x04)
        `uvm_info(get_type_name(), "Sub-iteration 1: Start Addr = 0x1001 (+1B), Len = 15B, Tag = 0x04", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter1");
        rd_seq.start_addr = 16'h1001;
        rd_seq.xfer_len   = 15;
        rd_seq.xfer_tag   = 8'h04;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #400;

        // Sub-iteration 2: Offset +2 Bytes (start_addr = 0x1002, len = 14, tag = 0x05)
        `uvm_info(get_type_name(), "Sub-iteration 2: Start Addr = 0x1002 (+2B), Len = 14B, Tag = 0x05", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter2");
        rd_seq.start_addr = 16'h1002;
        rd_seq.xfer_len   = 14;
        rd_seq.xfer_tag   = 8'h05;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #400;

        // Sub-iteration 3: Offset +3 Bytes (start_addr = 0x1003, len = 13, tag = 0x06)
        `uvm_info(get_type_name(), "Sub-iteration 3: Start Addr = 0x1003 (+3B), Len = 13B, Tag = 0x06", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter3");
        rd_seq.start_addr = 16'h1003;
        rd_seq.xfer_len   = 13;
        rd_seq.xfer_tag   = 8'h06;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #400;

        #500;
        phase.drop_objection(this, "Completed MM2S_04 Unaligned Test");
    endtask : run_phase

endclass : dma_rd_unaligned_test

`endif // DMA_RD_UNALIGNED_TEST_SV
