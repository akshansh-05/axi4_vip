// File: dma_rd_multiburst_test.sv
// Description: Multi-burst read transfer test (MM2S_02).
//              Verifies automatic slicing of a 256-byte read descriptor
//              into 4 consecutive 16-beat AXI read bursts.

`ifndef DMA_RD_MULTIBURST_TEST_SV
`define DMA_RD_MULTIBURST_TEST_SV

class dma_rd_multiburst_test extends dma_base_test;

    typedef dma_rd_desc_multiburst_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) seq_type;

    `uvm_component_utils(dma_rd_multiburst_test)

    function new(string name = "dma_rd_multiburst_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        seq_type rd_seq;

        phase.raise_objection(this, "Starting Multi-Burst Test");

        `uvm_info(get_type_name(), "Starting Multi-Burst Test", UVM_LOW)

        rd_seq = seq_type::type_id::create("rd_seq");
        rd_seq.start_addr = 16'h1000;
        rd_seq.xfer_len   = 256;
        rd_seq.xfer_tag   = 8'h02;

        rd_seq.start(env.dma_rd_desc_agent.seqr);

        #800;
        `uvm_info(get_type_name(), "Multi-Burst transfer completed", UVM_LOW)

        #500;

        phase.drop_objection(this, "Completed Multi-Burst Test");
    endtask : run_phase

endclass : dma_rd_multiburst_test

`endif // DMA_RD_MULTIBURST_TEST_SV
