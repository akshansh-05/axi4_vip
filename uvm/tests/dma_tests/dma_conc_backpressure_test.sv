// File: dma_conc_backpressure_test.sv
// Description: Feature Test for CONC_04: Concurrent Dual-Channel Backpressure.
//              Verifies complete flow-control independence and deadlock immunity
//              under opposing heavy backpressure:
//              - MM2S Stream Sink asserts randomized inter-beat TREADY jitter and stalls.
//              - AXI Write Slave asserts heavy AWREADY and WREADY stalls and delays BVALID.
//              Validates that neither pipeline deadlocks, stalls cross-leak, or data corrupts.

`ifndef DMA_CONC_BACKPRESSURE_TEST_SV
`define DMA_CONC_BACKPRESSURE_TEST_SV

class dma_conc_backpressure_test extends dma_base_test;
  
  typedef dma_rd_desc_nominal_seq#(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) rd_desc_seq_type;
  typedef axis_rd_backpressure_seq#(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) axis_rd_bp_seq_type;
  typedef dma_wr_desc_backpressure_seq#(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
  typedef axis_packet_seq#(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) axis_wr_pkt_seq_type;
  
  `uvm_component_utils(dma_conc_backpressure_test)
  
  function new(string name = "dma_conc_backpressure_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new
  
  // Configure AXI-Stream Read VIP into sequence-driven reactive slave mode
  virtual function void configure_agents(cfg_type c_wr, cfg_type c_rd, dma_cfg_type c_dma_rd, dma_cfg_type c_dma_wr, axis_cfg_type c_axis_wr, axis_cfg_type c_axis_rd);
    super.configure_agents(c_wr, c_rd, c_dma_rd, c_dma_wr, c_axis_wr, c_axis_rd);
    c_axis_rd.ready_always_high = 1'b0; // Enable sequence-controlled TREADY backpressure
  endfunction : configure_agents
  
  virtual task run_phase(uvm_phase phase);
    rd_desc_seq_type rd_desc_seq;
    axis_rd_bp_seq_type stream_rd_seq;
    wr_desc_seq_type wr_desc_seq;
    axis_wr_pkt_seq_type axis_wr_pkt_seq;
    
    phase.raise_objection(this, "Starting CONC_04 Dual-Channel Backpressure Test");
    
    `uvm_info(get_type_name(), "Starting CONC_04: Concurrent Dual-Channel Backpressure Stress", UVM_LOW)
    `uvm_info(get_type_name(), "MM2S: TREADY Jitter Stalls | S2MM: AWREADY/WREADY Memory Stalls", UVM_LOW)
    
    // 1. Configure Memory Slave Write Backpressure Knobs
    cfg_wr.enable_awready_stall = 1'b1;
    cfg_wr.min_awready_delay = 3;
    cfg_wr.max_awready_delay = 6;
    cfg_wr.enable_wready_stall = 1'b1;
    cfg_wr.wready_stall_period = 4;
    cfg_wr.wready_stall_cycles = 3;
    cfg_wr.bvalid_delay = 3;
    
    // 2. Configure Stream Read Slave Backpressure Sequence (Jittered TREADY)
    stream_rd_seq = axis_rd_bp_seq_type::type_id::create("stream_rd_seq");
    stream_rd_seq.bp_mode = AXIS_BP_FULL_JITTER;
    stream_rd_seq.num_beats = 16;
    stream_rd_seq.min_jitter = 1;
    stream_rd_seq.max_jitter = 3;
    stream_rd_seq.final_stall = 3;
    
    // 3. Configure MM2S Read Descriptor Sequence (64 B at 0x1000, tag 0x31)
    rd_desc_seq = rd_desc_seq_type::type_id::create("rd_desc_seq");
    rd_desc_seq.start_addr = 16'h1000;
    rd_desc_seq.xfer_len = 64;
    rd_desc_seq.xfer_tag = 8'h31;
    
    // 4. Configure S2MM Write Descriptor Sequence (64 B to 0x2000, tag 0x32)
    wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq");
    wr_desc_seq.dest_addr = 16'h2000;
    wr_desc_seq.buffer_len = 64;
    wr_desc_seq.xfer_tag = 8'h32;
    
    // 5. Configure S2MM Ingress Stream Packet Sequence (16 beats = 64 bytes)
    axis_wr_pkt_seq = axis_wr_pkt_seq_type::type_id::create("axis_wr_pkt_seq");
    axis_wr_pkt_seq.num_packets = 1;
    axis_wr_pkt_seq.min_beats = 16;
    axis_wr_pkt_seq.max_beats = 16;
    axis_wr_pkt_seq.force_full_last_keep = 1'b1;
    axis_wr_pkt_seq.max_delay = 0;
    
    // 6. Launch 4-way concurrent full-duplex traffic with opposing backpressure
    fork
      begin
        `uvm_info(get_type_name(), "Fork Branch 1: Starting MM2S Reactive Stream Sink Sequence", UVM_LOW)
        stream_rd_seq.start(env.axis_rd_agent.seqr);
        `uvm_info(get_type_name(), "Fork Branch 1: MM2S Stream Sink Sequence Finished", UVM_LOW)
      end
      begin
        `uvm_info(get_type_name(), "Fork Branch 2: Starting MM2S Read Descriptor Sequence", UVM_LOW)
        rd_desc_seq.start(env.dma_rd_desc_agent.seqr);
        `uvm_info(get_type_name(), "Fork Branch 2: MM2S Read Descriptor Finished", UVM_LOW)
      end
      begin
        `uvm_info(get_type_name(), "Fork Branch 3: Starting S2MM Write Descriptor Sequence", UVM_LOW)
        wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
        `uvm_info(get_type_name(), "Fork Branch 3: S2MM Write Descriptor Finished", UVM_LOW)
      end
      begin
        `uvm_info(get_type_name(), "Fork Branch 4: Starting S2MM Stream Ingress Sequence", UVM_LOW)
        axis_wr_pkt_seq.start(env.axis_wr_agent.seqr);
        `uvm_info(get_type_name(), "Fork Branch 4: S2MM Stream Ingress Finished", UVM_LOW)
      end
    join
    
    // 7. Post-transfer settlement time
    #400;
    `uvm_info(get_type_name(), "CONC_04: Dual-Channel Backpressure Test Completed with Zero Deadlock", UVM_LOW)
    
    #500;
    phase.drop_objection(this, "Completed CONC_04 Dual-Channel Backpressure Test");
  endtask : run_phase
  
endclass : dma_conc_backpressure_test

`endif // DMA_CONC_BACKPRESSURE_TEST_SV