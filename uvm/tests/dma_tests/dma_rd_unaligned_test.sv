// File: dma_rd_unaligned_test.sv
// Description: Feature Test for MM2S_04: Unaligned Start Address & TKEEP Lane Offsets.
//              Structured in 2 parts across 6 sequential sub-iterations:
//              - Part 1 (Single-Burst): Start address offsets +1B (0x1001), +2B (0x1002),
//                and +3B (0x1003) with transfer lengths 15B, 14B, 13B.
//              - Part 2 (Multi-Burst): Start address offsets +1B (0x2001), +2B (0x2002),
//                and +3B (0x2003) with transfer lengths 255B, 254B, 253B to verify
//                barrel-shifter alignment across AXI burst boundaries.

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

        `uvm_info(get_type_name(), "Starting MM2S_04 Unaligned Read Test (6 Sub-Iterations: Single-Burst & Multi-Burst)", UVM_LOW)

        // Part 1: Single-Burst Unaligned Alignment & Lane Offsets
        // Sub-iteration 1: Offset +1 Byte (start_addr = 0x1001, len = 15, tag = 0x04)
        `uvm_info(get_type_name(), "Sub-iteration 1: Single-Burst Start Addr = 0x1001 (+1B), Len = 15B, Tag = 0x04", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter1");
        rd_seq.start_addr = 16'h1001;
        rd_seq.xfer_len   = 15;
        rd_seq.xfer_tag   = 8'h04;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #400;

        // Sub-iteration 2: Offset +2 Bytes (start_addr = 0x1002, len = 14, tag = 0x05)
        `uvm_info(get_type_name(), "Sub-iteration 2: Single-Burst Start Addr = 0x1002 (+2B), Len = 14B, Tag = 0x05", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter2");
        rd_seq.start_addr = 16'h1002;
        rd_seq.xfer_len   = 14;
        rd_seq.xfer_tag   = 8'h05;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #400;

        // Sub-iteration 3: Offset +3 Bytes (start_addr = 0x1003, len = 13, tag = 0x06)
        `uvm_info(get_type_name(), "Sub-iteration 3: Single-Burst Start Addr = 0x1003 (+3B), Len = 13B, Tag = 0x06", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter3");
        rd_seq.start_addr = 16'h1003;
        rd_seq.xfer_len   = 13;
        rd_seq.xfer_tag   = 8'h06;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #400;

        // Part 2: Multi-Burst Unaligned Slicing & Burst-Boundary Barrel Shifting
        // Sub-iteration 4: Offset +1 Byte (start_addr = 0x2001, len = 255, tag = 0x14)
        `uvm_info(get_type_name(), "Sub-iteration 4: Multi-Burst Start Addr = 0x2001 (+1B), Len = 255B, Tag = 0x14", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter4");
        rd_seq.start_addr = 16'h2001;
        rd_seq.xfer_len   = 255;
        rd_seq.xfer_tag   = 8'h14;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #800;

        // Sub-iteration 5: Offset +2 Bytes (start_addr = 0x2002, len = 254, tag = 0x15)
        `uvm_info(get_type_name(), "Sub-iteration 5: Multi-Burst Start Addr = 0x2002 (+2B), Len = 254B, Tag = 0x15", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter5");
        rd_seq.start_addr = 16'h2002;
        rd_seq.xfer_len   = 254;
        rd_seq.xfer_tag   = 8'h15;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #800;

        // Sub-iteration 6: Offset +3 Bytes (start_addr = 0x2003, len = 253, tag = 0x16)
        `uvm_info(get_type_name(), "Sub-iteration 6: Multi-Burst Start Addr = 0x2003 (+3B), Len = 253B, Tag = 0x16", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter6");
        rd_seq.start_addr = 16'h2003;
        rd_seq.xfer_len   = 253;
        rd_seq.xfer_tag   = 8'h16;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #800;

        #500;
        phase.drop_objection(this, "Completed MM2S_04 Unaligned Test");
    endtask : run_phase

endclass : dma_rd_unaligned_test

`endif // DMA_RD_UNALIGNED_TEST_SV
