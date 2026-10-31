// File: dma_rd_4kb_split_test.sv
// Description: Feature Test for MM2S_03: 4KB Boundary Crossing Read Split.
//              Structured in 2 sequential sub-iterations:
//              - Sub-iteration 1 (Single-Burst Split): 64-byte descriptor starting at
//                0x0FE0, legally clamped and split into two 8-beat bursts (0x0FE0 and 0x1000).
//              - Sub-iteration 2 (Multi-Burst Split): 128-byte descriptor starting at
//                0x0FE0, split into 32B burst at 0x0FE0, followed by a full 16-beat (64B)
//                burst at 0x1000, and a final 32B burst at 0x1040.

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

        `uvm_info(get_type_name(), "Starting MM2S_03 4KB Split Test (2 Sub-Iterations: 64B & 128B across 0x1000)", UVM_LOW)

        // Sub-iteration 1: Single-Burst Split (64 Bytes across 4KB boundary at 0x1000)
        `uvm_info(get_type_name(), "Sub-iteration 1: 64B Split (32B @ 0x0FE0, 32B @ 0x1000, Tag 0x03)", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter1");
        rd_seq.start_addr = 16'h0FE0;
        rd_seq.xfer_len   = 64;
        rd_seq.xfer_tag   = 8'h03;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #600;

        // Sub-iteration 2: Multi-Burst Split (128 Bytes across 4KB boundary at 0x1000)
        `uvm_info(get_type_name(), "Sub-iteration 2: 128B Multi-Burst Split (32B @ 0x0FE0, 64B @ 0x1000, 32B @ 0x1040, Tag 0x13)", UVM_LOW)
        rd_seq = seq_type::type_id::create("rd_seq_iter2");
        rd_seq.start_addr = 16'h0FE0;
        rd_seq.xfer_len   = 128;
        rd_seq.xfer_tag   = 8'h04;
        rd_seq.start(env.dma_rd_desc_agent.seqr);
        #800;

        #500;
        phase.drop_objection(this, "Completed MM2S_03 4KB Split Test");
    endtask : run_phase

endclass : dma_rd_4kb_split_test

`endif // DMA_RD_4KB_SPLIT_TEST_SV
