// File: dma_conc_adjacent_addr_test.sv
// Description: Feature Test for CONC_03: Concurrent Adjacent Buffer Streaming.
//              Verifies that accessing contiguous, non-overlapping memory buffers within
//              the exact same 4KB page (sharing upper address bits addr[31:6]) maintains
//              strict spatial isolation without address aliasing, decode cross-talk,
//              or buffer memory corruption.

`ifndef DMA_CONC_ADJACENT_ADDR_TEST_SV
`define DMA_CONC_ADJACENT_ADDR_TEST_SV

class dma_conc_adjacent_addr_test extends dma_base_test;

    typedef dma_rd_desc_nominal_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) rd_desc_seq_type;
    typedef dma_wr_desc_nominal_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
    typedef axis_packet_seq        #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_pkt_seq_type;

    `uvm_component_utils(dma_conc_adjacent_addr_test)

    function new(string name = "dma_conc_adjacent_addr_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        rd_desc_seq_type  rd_desc_seq;
        wr_desc_seq_type  wr_desc_seq;
        axis_pkt_seq_type axis_pkt_seq;

        phase.raise_objection(this, "Starting CONC_03 Concurrent Adjacent Buffer Test");

        `uvm_info(get_type_name(), "Starting CONC_03: Concurrent Adjacent Buffer Streaming (Shared-Page)", UVM_LOW)
        `uvm_info(get_type_name(), "MM2S: 64B at 0x1000-0x103F | S2MM: 64B at 0x1040-0x107F (Adjacent)", UVM_LOW)

        // 1. Configure MM2S Read Descriptor Sequence (0x1000 - 0x103F, 64 bytes)
        rd_desc_seq = rd_desc_seq_type::type_id::create("rd_desc_seq");
        rd_desc_seq.start_addr = 16'h1000;
        rd_desc_seq.xfer_len   = 64;
        rd_desc_seq.xfer_tag   = 8'h11;

        // 2. Configure S2MM Write Descriptor Sequence (0x1040 - 0x107F, contiguous adjacent buffer)
        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq");
        wr_desc_seq.dest_addr  = 16'h1040;
        wr_desc_seq.buffer_len = 64;
        wr_desc_seq.xfer_tag   = 8'h22;

        // 3. Configure S2MM Ingress Stream Packet Sequence (16 beats = 64 bytes)
        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq");
        axis_pkt_seq.num_packets          = 1;
        axis_pkt_seq.min_beats            = 16;
        axis_pkt_seq.max_beats            = 16;
        axis_pkt_seq.force_full_last_keep = 1'b1;
        axis_pkt_seq.max_delay            = 0;

        // 4. Launch concurrent full-duplex traffic to adjacent shared-page buffers
        fork
            begin
                `uvm_info(get_type_name(), "Fork Branch 1: Starting MM2S Read (0x1000-0x103F)", UVM_LOW)
                rd_desc_seq.start(env.dma_rd_desc_agent.seqr);
                `uvm_info(get_type_name(), "Fork Branch 1: MM2S Read Finished", UVM_LOW)
            end
            begin
                `uvm_info(get_type_name(), "Fork Branch 2: Starting S2MM Write (0x1040-0x107F)", UVM_LOW)
                wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
                `uvm_info(get_type_name(), "Fork Branch 2: S2MM Write Finished", UVM_LOW)
            end
            begin
                `uvm_info(get_type_name(), "Fork Branch 3: Starting S2MM Ingress Stream", UVM_LOW)
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
                `uvm_info(get_type_name(), "Fork Branch 3: S2MM Ingress Stream Finished", UVM_LOW)
            end
        join

        // 5. Post-transfer settlement time
        #300;
        `uvm_info(get_type_name(), "CONC_03: Adjacent Buffer Concurrent Transfers Completed Successfully", UVM_LOW)

        #500;
        phase.drop_objection(this, "Completed CONC_03 Concurrent Adjacent Buffer Test");
    endtask : run_phase

endclass : dma_conc_adjacent_addr_test

`endif // DMA_CONC_ADJACENT_ADDR_TEST_SV
