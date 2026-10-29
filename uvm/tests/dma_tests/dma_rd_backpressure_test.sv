// File: dma_rd_backpressure_test.sv
// Description: Feature Test for MM2S_06: Stream Destination Backpressure & Pipeline Flow Control.
//              Structured in 3 sequential phases (executing Phase 1 first for isolated verification):
//              - Phase 1: Stage 2 ARREADY Stall & Inter-Descriptor Lockout (Tags 0x0A & 0x0B) [ACTIVE]
//              - Phase 2: Stage 4/5 Skid FIFO Half-Full Watermark & Upstream RREADY Clamping (Tag 0x0C) [DEFERRED]
//              - Phase 3: Full-Pipeline Simultaneous Jitter & TLAST Status Synchronization (Tag 0x0D) [DEFERRED]

`ifndef DMA_RD_BACKPRESSURE_TEST_SV
`define DMA_RD_BACKPRESSURE_TEST_SV

class dma_rd_backpressure_test extends dma_base_test;

    typedef dma_rd_desc_backpressure_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) desc_seq_type;
    typedef axis_rd_backpressure_seq     #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) stream_seq_type;

    `uvm_component_utils(dma_rd_backpressure_test)

    function new(string name = "dma_rd_backpressure_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void configure_agents(
        cfg_type c_wr, cfg_type c_rd,
        dma_cfg_type c_dma_rd, dma_cfg_type c_dma_wr,
        axis_cfg_type c_axis_wr, axis_cfg_type c_axis_rd
    );
        super.configure_agents(c_wr, c_rd, c_dma_rd, c_dma_wr, c_axis_wr, c_axis_rd);

        // Configure AXI-Stream VIP into sequence-driven reactive slave mode
        c_axis_rd.ready_always_high = 1'b0;
    endfunction : configure_agents

    virtual task run_phase(uvm_phase phase);
        desc_seq_type   desc_seq1, desc_seq2;
        stream_seq_type stream_seq;

        phase.raise_objection(this, "Starting MM2S_06 Pipeline Backpressure Test");

        `uvm_info(get_type_name(), "Starting MM2S_06 Pipeline Backpressure Test (Phase 1 Active)", UVM_LOW)

        // Phase 1: Stage 2 ARREADY Stall & Inter-Descriptor Lockout
        `uvm_info(get_type_name(), "Executing Phase 1: Stage 2 ARREADY Stall (5 cycles) & Descriptor Lockout (Tags 0x0A, 0x0B)", UVM_LOW)
        cfg_rd.enable_arready_stall = 1'b1;
        cfg_rd.min_arready_delay    = 5;
        cfg_rd.max_arready_delay    = 5;
        cfg_rd.initial_rdata_delay  = 0;
        cfg_rd.enable_r_bubbles     = 1'b0;

        desc_seq1 = desc_seq_type::type_id::create("desc_seq1");
        desc_seq1.start_addr = 16'h1000;
        desc_seq1.xfer_len   = 64;
        desc_seq1.xfer_tag   = 8'h0A;

        desc_seq2 = desc_seq_type::type_id::create("desc_seq2");
        desc_seq2.start_addr = 16'h2000;
        desc_seq2.xfer_len   = 64;
        desc_seq2.xfer_tag   = 8'h0B;

        stream_seq = stream_seq_type::type_id::create("stream_seq_iter1");
        stream_seq.bp_mode   = AXIS_BP_ZERO_DELAY;
        stream_seq.num_beats = 32;

        fork
            stream_seq.start(env.axis_rd_agent.seqr);
            begin
                desc_seq1.start(env.dma_rd_desc_agent.seqr);
                desc_seq2.start(env.dma_rd_desc_agent.seqr);
            end
        join
        #300;

        // Phase 2: Stage 4 & 5 Skid FIFO Half-Full Watermark & Upstream RREADY Clamping
        `uvm_info(get_type_name(), "Sub-iteration 2: Sustained 20-cycle TREADY freeze midway -> RREADY clamping (Tag 0x0C)", UVM_LOW)
        cfg_rd.enable_arready_stall = 1'b0;
        cfg_rd.initial_rdata_delay  = 0;
        cfg_rd.enable_r_bubbles     = 1'b0;

        desc_seq3 = desc_seq_type::type_id::create("desc_seq3");
        desc_seq3.start_addr = 16'h3000;
        desc_seq3.xfer_len   = 64;
        desc_seq3.xfer_tag   = 8'h0C;

        stream_seq = stream_seq_type::type_id::create("stream_seq_iter2");
        stream_seq.bp_mode       = AXIS_BP_MIDWAY_FREEZE;
        stream_seq.num_beats     = 16;
        stream_seq.freeze_beat   = 7;
        stream_seq.freeze_cycles = 20;

        fork
            stream_seq.start(env.axis_rd_agent.seqr);
            desc_seq3.start(env.dma_rd_desc_agent.seqr);
        join
        #400;

        // Phase 3: Full-Pipeline Simultaneous Jitter & TLAST Status Synchronization
        `uvm_info(get_type_name(), "Sub-iteration 3: Full-Pipeline Concurrent Jitter & TLAST Status Sync (Tag 0x0D)", UVM_LOW)
        cfg_rd.enable_arready_stall = 1'b1;
        cfg_rd.min_arready_delay    = 2;
        cfg_rd.max_arready_delay    = 3;
        cfg_rd.initial_rdata_delay  = 2;
        cfg_rd.enable_r_bubbles     = 1'b1;
        cfg_rd.min_r_bubble         = 1;
        cfg_rd.max_r_bubble         = 2;

        desc_seq4 = desc_seq_type::type_id::create("desc_seq4");
        desc_seq4.start_addr = 16'h4000;
        desc_seq4.xfer_len   = 64;
        desc_seq4.xfer_tag   = 8'h0D;

        stream_seq = stream_seq_type::type_id::create("stream_seq_iter3");
        stream_seq.bp_mode     = AXIS_BP_FULL_JITTER;
        stream_seq.num_beats   = 16;
        stream_seq.min_jitter  = 1;
        stream_seq.max_jitter  = 3;
        stream_seq.final_stall = 3;

        fork
            stream_seq.start(env.axis_rd_agent.seqr);
            desc_seq4.start(env.dma_rd_desc_agent.seqr);
        join
        #500;

        #500;
        phase.drop_objection(this, "Completed MM2S_06 Pipeline Backpressure Test (All 3 Phases)");
    endtask : run_phase

endclass : dma_rd_backpressure_test

`endif // DMA_RD_BACKPRESSURE_TEST_SV
