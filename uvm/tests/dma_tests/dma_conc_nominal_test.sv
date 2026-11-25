// File: dma_conc_nominal_test.sv
// Description: Feature Test for CONC_01: Concurrent Nominal Bi-Directional Streaming.
//              Verifies baseline full-duplex operation with simultaneous MM2S read
//              (Memory -> Stream) and S2MM write (Stream -> Memory) transfers.
//              Both engines execute single-burst 64-byte transfers with word-aligned
//              disjoint memory buffers under ideal, unthrottled bus conditions.

`ifndef DMA_CONC_NOMINAL_TEST_SV
`define DMA_CONC_NOMINAL_TEST_SV

class dma_conc_nominal_test extends dma_base_test;
  
  typedef dma_rd_desc_nominal_seq#(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) rd_desc_seq_type;
  typedef dma_wr_desc_nominal_seq#(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
  typedef axis_packet_seq#(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) axis_pkt_seq_type;
  
  `uvm_component_utils(dma_conc_nominal_test)
  
  function new(string name = "dma_conc_nominal_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new
  
  virtual task run_phase(uvm_phase phase);
    rd_desc_seq_type rd_desc_seq;
    wr_desc_seq_type wr_desc_seq;
    axis_pkt_seq_type axis_pkt_seq;
    
    phase.raise_objection(this, "Starting CONC_01 Concurrent Nominal Test");
    
    `uvm_info(get_type_name(), "Starting CONC_01: Concurrent Nominal Bi-Directional Streaming", UVM_LOW)
    `uvm_info(get_type_name(), "MM2S: 64B from 0x1000 | S2MM: 64B to 0x2000 | Full Duplex", UVM_LOW)
    
    // 1. Configure MM2S Read Descriptor Sequence (64 bytes from 0x1000, tag 0x01)
    rd_desc_seq = rd_desc_seq_type::type_id::create("rd_desc_seq");
    rd_desc_seq.start_addr = 16'h1000;
    rd_desc_seq.xfer_len = 64;
    rd_desc_seq.xfer_tag = 8'h01;
    
    // 2. Configure S2MM Write Descriptor Sequence (64 bytes to 0x2000, tag 0x02)
    wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq");
    wr_desc_seq.dest_addr = 16'h2000;
    wr_desc_seq.buffer_len = 64;
    wr_desc_seq.xfer_tag = 8'h02;
    
    // 3. Configure S2MM Ingress Stream Packet Sequence (16 beats x 4 bytes = 64 bytes)
    axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq");
    axis_pkt_seq.num_packets = 1;
    axis_pkt_seq.min_beats = 16;
    axis_pkt_seq.max_beats = 16;
    axis_pkt_seq.force_full_last_keep = 1'b1; // Guarantee 4'b1111 on final beat
    axis_pkt_seq.max_delay = 0; // Wire-speed streaming without bubbles
    
    // 4. Launch concurrent full-duplex traffic
    fork
      begin
        `uvm_info(get_type_name(), "Fork Branch 1: Starting MM2S Read Descriptor Sequence", UVM_LOW)
        rd_desc_seq.start(env.dma_rd_desc_agent.seqr);
        `uvm_info(get_type_name(), "Fork Branch 1: MM2S Read Descriptor Sequence Finished", UVM_LOW)
      end
      begin
        `uvm_info(get_type_name(), "Fork Branch 2: Starting S2MM Write Descriptor Sequence", UVM_LOW)
        wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
        `uvm_info(get_type_name(), "Fork Branch 2: S2MM Write Descriptor Sequence Finished", UVM_LOW)
      end
      begin
        `uvm_info(get_type_name(), "Fork Branch 3: Starting S2MM AXI-Stream Ingress Packet Sequence", UVM_LOW)
        axis_pkt_seq.start(env.axis_wr_agent.seqr);
        `uvm_info(get_type_name(), "Fork Branch 3: S2MM AXI-Stream Ingress Packet Sequence Finished", UVM_LOW)
      end
    join
    
    // 5. Post-transfer settlement time to allow final write response and stream drains
    #300;
    `uvm_info(get_type_name(), "CONC_01: Concurrent Full-Duplex Transfers Completed", UVM_LOW)
    
    #500;
    phase.drop_objection(this, "Completed CONC_01 Concurrent Nominal Test");
  endtask : run_phase
  
endclass : dma_conc_nominal_test

`endif // DMA_CONC_NOMINAL_TEST_SV