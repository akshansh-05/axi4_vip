// File: dma_conc_identical_tag_test.sv
// Description: Feature Test for CONC_02: Concurrent Transfers with Identical Descriptor Tags.
//              Verifies that MM2S and S2MM descriptor tracking, command queues, and status
//              reporting operate in completely isolated namespaces. Both engines receive
//              the identical tag (0xA5) simultaneously, verifying zero tag aliasing or collision.

`ifndef DMA_CONC_IDENTICAL_TAG_TEST_SV
`define DMA_CONC_IDENTICAL_TAG_TEST_SV

class dma_conc_identical_tag_test extends dma_base_test;
  
  typedef dma_rd_desc_nominal_seq#(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) rd_desc_seq_type;
  typedef dma_wr_desc_nominal_seq#(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) wr_desc_seq_type;
  typedef axis_packet_seq#(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) axis_pkt_seq_type;
  
  `uvm_component_utils(dma_conc_identical_tag_test)
  
  function new(string name = "dma_conc_identical_tag_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new
  
  virtual task run_phase(uvm_phase phase);
    rd_desc_seq_type rd_desc_seq;
    wr_desc_seq_type wr_desc_seq;
    axis_pkt_seq_type axis_pkt_seq;
    
    phase.raise_objection(this, "Starting CONC_02 Concurrent Identical Tag Test");
    
    `uvm_info(get_type_name(), "Starting CONC_02: Concurrent Identical Tag Namespace Isolation", UVM_LOW)
    `uvm_info(get_type_name(), "MM2S Tag: 0xA5 (0x1000) | S2MM Tag: 0xA5 (0x2000) | Identical Tags", UVM_LOW)
    
    // 1. Configure MM2S Read Descriptor Sequence with Tag 0xA5
    rd_desc_seq = rd_desc_seq_type::type_id::create("rd_desc_seq");
    rd_desc_seq.start_addr = 16'h1000;
    rd_desc_seq.xfer_len = 64;
    rd_desc_seq.xfer_tag = 8'hA5; // Shared tag value
    
    // 2. Configure S2MM Write Descriptor Sequence with Identical Tag 0xA5
    wr_desc_seq = wr_desc_seq_type::type_id::create("wr_desc_seq");
    wr_desc_seq.dest_addr = 16'h2000;
    wr_desc_seq.buffer_len = 64;
    wr_desc_seq.xfer_tag = 8'hA5; // Shared tag value
    
    // 3. Configure S2MM Ingress Stream Packet Sequence (16 beats = 64 bytes)
    axis_pkt_seq = axis_pkt_seq_type::type_id::create("axis_pkt_seq");
    axis_pkt_seq.num_packets = 1;
    axis_pkt_seq.min_beats = 16;
    axis_pkt_seq.max_beats = 16;
    axis_pkt_seq.force_full_last_keep = 1'b1;
    axis_pkt_seq.max_delay = 0;
    
    // 4. Launch concurrent full-duplex traffic with identical tags
    fork
      begin
        `uvm_info(get_type_name(), "Fork Branch 1: Starting MM2S Read Descriptor (Tag 0xA5)", UVM_LOW)
        rd_desc_seq.start(env.dma_rd_desc_agent.seqr);
        `uvm_info(get_type_name(), "Fork Branch 1: MM2S Read Descriptor Finished", UVM_LOW)
      end
      begin
        `uvm_info(get_type_name(), "Fork Branch 2: Starting S2MM Write Descriptor (Tag 0xA5)", UVM_LOW)
        wr_desc_seq.start(env.dma_wr_desc_agent.seqr);
        `uvm_info(get_type_name(), "Fork Branch 2: S2MM Write Descriptor Finished", UVM_LOW)
      end
      begin
        `uvm_info(get_type_name(), "Fork Branch 3: Starting S2MM Stream Ingress", UVM_LOW)
        axis_pkt_seq.start(env.axis_wr_agent.seqr);
        `uvm_info(get_type_name(), "Fork Branch 3: S2MM Stream Ingress Finished", UVM_LOW)
      end
    join
    
    // 5. Post-transfer settlement time
    #300;
    `uvm_info(get_type_name(), "CONC_02: Concurrent Transfers with Identical Tags Completed Successfully", UVM_LOW)
    
    #500;
    phase.drop_objection(this, "Completed CONC_02 Concurrent Identical Tag Test");
  endtask : run_phase
  
endclass : dma_conc_identical_tag_test

`endif // DMA_CONC_IDENTICAL_TAG_TEST_SV