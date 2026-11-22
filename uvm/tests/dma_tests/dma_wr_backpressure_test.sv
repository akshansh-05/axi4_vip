// File: dma_wr_backpressure_test.sv
// Description: Feature Test for S2MM_09: Memory Bus Write Backpressure & System Contention.
//              Verifies that when the memory slave inserts backpressure on AWREADY,
//              WREADY, and delays BVALID, the DMA write engine throttles ingress stream
//              TREADY and completes transfers without dropping or duplicating data:
//              - Sub-iteration 1: Pure downstream memory bus backpressure (64B, Tag 0x13) at full wire speed.
//              - Sub-iteration 2: Concurrent multi-burst push-pull contention (128B, Tag 0x14)
//                with stream bubbles, AW/W stalls, and delayed BVALID.

`ifndef DMA_WR_BACKPRESSURE_TEST_SV
`define DMA_WR_BACKPRESSURE_TEST_SV

class dma_wr_backpressure_test extends dma_base_test;

    typedef dma_wr_desc_backpressure_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
    typedef axis_packet_seq              #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_pkt_seq_type;

    `uvm_component_utils(dma_wr_backpressure_test)

    function new(string name = "dma_wr_backpressure_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        wr_desc_seq_type  wr_desc_seq;
        axis_pkt_seq_type axis_pkt_seq;

        phase.raise_objection(this, "Starting S2MM_09 Memory Bus Write Backpressure Test");

        `uvm_info(get_type_name(), "Starting S2MM_09 Write Backpressure Test (Sub-iter 1: Wire-Speed Stalls, Sub-iter 2: Multi-Burst Push-Pull)", UVM_LOW)

        // Sub-iteration 1: Pure Downstream Memory Backpressure at Full Wire Speed (Tag 0x13)
        `uvm_info(get_type_name(), "Executing Sub-iteration 1: Pure Downstream Memory Backpressure (Tag 0x13)", UVM_LOW)

        cfg_wr.enable_awready_stall = 1'b1;
        cfg_wr.min_awready_delay    = 3;
        cfg_wr.max_awready_delay    = 6;
        cfg_wr.enable_wready_stall  = 1'b1;
        cfg_wr.wready_stall_period  = 4;
        cfg_wr.wready_stall_cycles  = 3;
        cfg_wr.bvalid_delay         = 3;

        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq_iter1");
        wr_desc_seq.dest_addr  = 16'h2000;
        wr_desc_seq.buffer_len = 64; // 16 beats = 64 bytes (single burst)
        wr_desc_seq.xfer_tag   = 8'h13;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter1");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 16;
        axis_pkt_seq.max_beats                = 16;
        axis_pkt_seq.force_full_last_keep     = 1'b1;
        axis_pkt_seq.inter_packet_delay       = 0;
        axis_pkt_seq.inter_beat_delay         = 0; // Pure wire-speed push
        axis_pkt_seq.initial_delay            = 0;
        axis_pkt_seq.enable_random_beat_delay = 0;
        axis_pkt_seq.max_delay                = 0;

        fork
            begin
                wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
            end
            begin
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
            end
        join
        #400;

        // Sub-iteration 2: Concurrent Multi-Burst Push-Pull Contention (Tag 0x14)
        `uvm_info(get_type_name(), "Executing Sub-iteration 2: Multi-Burst Push-Pull Contention (Tag 0x14)", UVM_LOW)

        cfg_wr.enable_awready_stall = 1'b1;
        cfg_wr.min_awready_delay    = 4;
        cfg_wr.max_awready_delay    = 8;
        cfg_wr.enable_wready_stall  = 1'b1;
        cfg_wr.wready_stall_period  = 3;
        cfg_wr.wready_stall_cycles  = 3;
        cfg_wr.bvalid_delay         = 4;

        wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq_iter2");
        wr_desc_seq.dest_addr  = 16'h3000;
        wr_desc_seq.buffer_len = 128; // 32 beats = 128 bytes (two 16-beat bursts)
        wr_desc_seq.xfer_tag   = 8'h14;

        axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq_iter2");
        axis_pkt_seq.num_packets              = 1;
        axis_pkt_seq.min_beats                = 32;
        axis_pkt_seq.max_beats                = 32;
        axis_pkt_seq.force_full_last_keep     = 1'b1;
        axis_pkt_seq.inter_packet_delay       = 0;
        axis_pkt_seq.inter_beat_delay         = 3; // Ingress stream bubbles
        axis_pkt_seq.initial_delay            = 0;
        axis_pkt_seq.enable_random_beat_delay = 1;
        axis_pkt_seq.max_delay                = 0;

        fork
            begin
                wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
            end
            begin
                axis_pkt_seq.start(env.axis_wr_agent.seqr);
            end
        join
        #600;

        // Reset memory slave knobs to defaults
        cfg_wr.enable_awready_stall = 1'b0;
        cfg_wr.enable_wready_stall  = 1'b0;
        cfg_wr.bvalid_delay         = 0;

        #500;
        phase.drop_objection(this, "Completed S2MM_09 Memory Bus Write Backpressure Test");
    endtask : run_phase

endclass : dma_wr_backpressure_test

`endif // DMA_WR_BACKPRESSURE_TEST_SV
