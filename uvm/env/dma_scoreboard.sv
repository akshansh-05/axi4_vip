// File: dma_scoreboard.sv
// Description: UVM Functional Scoreboard for AXI4 DMA Subsystem - MM2S Read Engine.
//              Contains 5 verification stages:
//              Stage 1: Command Registration (dma_rd_desc_monitor -> cmd_ap)
//              Stage 2: Memory Read Slicing & Burst Address Progression (axi_rd_monitor -> ap)
//              Stage 3: Egress Stream Collection & Packet Framing (axis_rd_monitor -> ap)
//              Stage 4: Incremental Pair-Wise Comparator (compare_mm2s_data)
//              Stage 5: Status Retirement & Cleanliness Check (dma_rd_desc_monitor -> status_ap)

`ifndef DMA_SCOREBOARD_SV
`define DMA_SCOREBOARD_SV

`ifndef DMA_RD_CMD_IMP_DECL
`define DMA_RD_CMD_IMP_DECL
`uvm_analysis_imp_decl(_dma_rd_cmd)
`endif

`ifndef DMA_RD_STATUS_IMP_DECL
`define DMA_RD_STATUS_IMP_DECL
`uvm_analysis_imp_decl(_dma_rd_status)
`endif

`ifndef AXIS_RD_IMP_DECL
`define AXIS_RD_IMP_DECL
`uvm_analysis_imp_decl(_axis_rd)
`endif

`ifndef AXI_RD_IMP_DECL
`define AXI_RD_IMP_DECL
`uvm_analysis_imp_decl(_axi_rd)
`endif

`ifndef DMA_WR_CMD_IMP_DECL
`define DMA_WR_CMD_IMP_DECL
`uvm_analysis_imp_decl(_dma_wr_cmd)
`endif

`ifndef DMA_WR_STATUS_IMP_DECL
`define DMA_WR_STATUS_IMP_DECL
`uvm_analysis_imp_decl(_dma_wr_status)
`endif

`ifndef AXIS_WR_IMP_DECL
`define AXIS_WR_IMP_DECL
`uvm_analysis_imp_decl(_axis_wr)
`endif

`ifndef AXI_WR_IMP_DECL
`define AXI_WR_IMP_DECL
`uvm_analysis_imp_decl(_axi_wr)
`endif

// Helper Descriptor Tracking Class for MM2S
class mm2s_desc_txn #(
    parameter ADDR_WIDTH = 16, parameter LEN_WIDTH = 20, parameter TAG_WIDTH = 8);
  bit[ADDR_WIDTH-1 : 0] start_addr;
  bit[LEN_WIDTH-1 : 0] xfer_len;
  bit[TAG_WIDTH-1 : 0] tag;
  byte expected_bytes[$]; // Golden bytes sliced from AXI-MM read bursts
  byte actual_bytes[$]; // Egress stream bytes observed on AXIS
  int unsigned total_bytes_expected;
  int unsigned bytes_matched;
  int unsigned packet_count; // Number of stream packets observed (must be exactly 1)
  int unsigned stream_pkt_bytes; // Total bytes in the observed stream packet
  bit[ADDR_WIDTH-1 : 0] expected_next_burst_addr; // Next expected AXI read burst address
  bit cmd_seen;
  bit stream_done;
  bit status_done;
  dma_error_e status_error;
  
  function new();
    expected_bytes = {};
    actual_bytes = {};
    total_bytes_expected = 0;
    bytes_matched = 0;
    packet_count = 0;
    stream_pkt_bytes = 0;
    expected_next_burst_addr = '0;
    cmd_seen = 1'b0;
    stream_done = 1'b0;
    status_done = 1'b0;
    status_error = DMA_ERR_NONE;
  endfunction
endclass : mm2s_desc_txn

// Helper Descriptor Tracking Class for S2MM
class s2mm_desc_txn #(
    parameter ADDR_WIDTH = 16, parameter LEN_WIDTH = 20, parameter TAG_WIDTH = 8);
  bit[ADDR_WIDTH-1 : 0] dest_addr;
  bit[LEN_WIDTH-1 : 0] buffer_len;
  bit[TAG_WIDTH-1 : 0] tag;
  byte expected_bytes[$]; // Golden bytes assembled from ingress stream
  byte actual_bytes[$]; // Bytes captured from AXI write bursts (where WSTRB=1)
  int unsigned total_stream_bytes;
  int unsigned total_written_bytes;
  int unsigned bytes_matched;
  bit[ADDR_WIDTH-1 : 0] expected_next_awaddr; // Progression check across multi-bursts
  bit cmd_seen;
  bit stream_done; // TLAST observed
  bit all_bursts_done; // All expected AW/W/B bursts completed
  bit status_done; // Descriptor status received
  dma_error_e status_error;
  bit[LEN_WIDTH-1 : 0] status_len;
  bit is_early_termination;
  bit is_excess_data;
  
  function new();
    expected_bytes = {};
    actual_bytes = {};
    total_stream_bytes = 0;
    total_written_bytes = 0;
    bytes_matched = 0;
    expected_next_awaddr = '0;
    cmd_seen = 1'b0;
    stream_done = 1'b0;
    all_bursts_done = 1'b0;
    status_done = 1'b0;
    status_error = DMA_ERR_NONE;
    status_len = '0;
    is_early_termination = 1'b0;
    is_excess_data = 1'b0;
  endfunction
endclass : s2mm_desc_txn

// Top DMA Scoreboard Component (MM2S Read Engine Focus)
class dma_scoreboard #(
    parameter DATA_WIDTH = 32, parameter ADDR_WIDTH = 16, parameter ID_WIDTH = 8, parameter STRB_WIDTH = (DATA_WIDTH / 8), parameter LEN_WIDTH = 20, parameter TAG_WIDTH = 8, parameter DEST_WIDTH = 8, parameter USER_WIDTH = 1) extends uvm_scoreboard;
  
  `uvm_component_param_utils(dma_scoreboard#(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH))
  
  typedef axi_seq_item#(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) axi_item_type;
  typedef axis_seq_item#(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) axis_item_type;
  typedef dma_desc_seq_item#(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) dma_desc_item_type;
  
  typedef mm2s_desc_txn#(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH) mm2s_txn_type;
  typedef s2mm_desc_txn#(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH) s2mm_txn_type;
  
  // 1. Analysis Exports (MM2S Ports)
  uvm_analysis_imp_dma_rd_cmd#(dma_desc_item_type, dma_scoreboard#(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_dma_rd_cmd;
  uvm_analysis_imp_dma_rd_status#(dma_desc_item_type, dma_scoreboard#(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_dma_rd_status;
  uvm_analysis_imp_axis_rd#(axis_item_type, dma_scoreboard#(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_axis_rd;
  uvm_analysis_imp_axi_rd#(axi_item_type, dma_scoreboard#(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_axi_rd;
  
  // 2. Analysis Exports (S2MM Ports)
  uvm_analysis_imp_dma_wr_cmd#(dma_desc_item_type, dma_scoreboard#(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_dma_wr_cmd;
  uvm_analysis_imp_dma_wr_status#(dma_desc_item_type, dma_scoreboard#(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_dma_wr_status;
  uvm_analysis_imp_axis_wr#(axis_item_type, dma_scoreboard#(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_axis_wr;
  uvm_analysis_imp_axi_wr#(axi_item_type, dma_scoreboard#(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_axi_wr;
  
  // 3. Internal Tracking Data Structures
  mm2s_txn_type mm2s_queue[$];
  mm2s_txn_type mm2s_by_tag[bit[TAG_WIDTH-1 : 0]];
  
  s2mm_txn_type s2mm_queue[$];
  s2mm_txn_type s2mm_by_tag[bit[TAG_WIDTH-1 : 0]];
  axis_item_type unmatched_axis_pkts[$]; // Buffers early stream packets in data-first timing skew scenarios
  
  // 4. Verification Statistics (MM2S)
  int unsigned mm2s_cmd_count = 0;
  int unsigned mm2s_status_count = 0;
  int unsigned mm2s_bytes_checked = 0;
  int unsigned mm2s_byte_matches = 0;
  int unsigned mm2s_byte_mismatches = 0;
  int unsigned mm2s_pkt_errors = 0;
  int unsigned mm2s_addr_errors = 0;
  int unsigned mm2s_status_mismatches = 0;
  int unsigned mm2s_hang_count = 0;
  
  // 5. Verification Statistics (S2MM)
  int unsigned s2mm_cmd_count = 0;
  int unsigned s2mm_status_count = 0;
  int unsigned s2mm_stream_pkt_count = 0;
  int unsigned s2mm_burst_count = 0;
  int unsigned s2mm_bytes_checked = 0;
  int unsigned s2mm_byte_matches = 0;
  int unsigned s2mm_byte_mismatches = 0;
  int unsigned s2mm_pkt_errors = 0;
  int unsigned s2mm_addr_errors = 0;
  int unsigned s2mm_status_mismatches = 0;
  int unsigned s2mm_hang_count = 0;
  
  // Constructor
  function new(string name = "dma_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    imp_dma_rd_cmd = new("imp_dma_rd_cmd", this);
    imp_dma_rd_status = new("imp_dma_rd_status", this);
    imp_axis_rd = new("imp_axis_rd", this);
    imp_axi_rd = new("imp_axi_rd", this);
    
    imp_dma_wr_cmd = new("imp_dma_wr_cmd", this);
    imp_dma_wr_status = new("imp_dma_wr_status", this);
    imp_axis_wr = new("imp_axis_wr", this);
    imp_axi_wr = new("imp_axi_wr", this);
  endfunction : new
  
  // Stage 1: Command Registration (dma_rd_desc_monitor -> cmd_ap)
  virtual function void write_dma_rd_cmd(dma_desc_item_type t);
    mm2s_txn_type desc;
    
    desc = new();
    desc.start_addr = t.addr;
    desc.xfer_len = t.len;
    desc.tag = t.tag;
    desc.total_bytes_expected = t.len;
    desc.expected_next_burst_addr = t.addr;
    desc.cmd_seen = 1'b1;
    
    mm2s_queue.push_back(desc);
    mm2s_by_tag[t.tag] = desc;
    mm2s_cmd_count++;
    
    `uvm_info("SCB_MM2S_CMD", $sformatf("Registered MM2S Read Descriptor: tag=0x%02h, addr=0x%04h, len=%0d bytes", t.tag, t.addr, t.len), UVM_MEDIUM)
  endfunction : write_dma_rd_cmd
  
  // Stage 2: Memory Read Slicing & Burst Address Progression (axi_rd_monitor -> ap)
  virtual function void write_axi_rd(axi_item_type t);
    mm2s_txn_type desc;
    
    if (mm2s_queue.size() == 0) begin
      `uvm_error("SCB_MM2S_UNEXP_RD", $sformatf("Observed AXI Read burst (addr=0x%04h) without active MM2S descriptor!", t.addr))
      return;
    end
    
    desc = mm2s_queue[0];
    
    // 1. Verify AXI Read burst address progression
    if (t.addr !== desc.expected_next_burst_addr) begin
      `uvm_error("SCB_MM2S_BURST_ADDR", $sformatf("MM2S AXI Read burst address mismatch for tag 0x%02h! Expected=0x%04h, Actual=0x%04h", desc.tag, desc.expected_next_burst_addr, t.addr))
      mm2s_addr_errors++;
    end
    desc.expected_next_burst_addr = (t.addr & ~(STRB_WIDTH - 1)) + ((t.len + 1) * STRB_WIDTH);
    
    // 2. Unpack 32-bit read data words into individual byte stream (Windowing)
    for (int i = 0; i <= t.len; i++) begin
      for (int b = 0; b < STRB_WIDTH; b++) begin
        int byte_addr = (t.addr & ~(STRB_WIDTH - 1)) + (i * STRB_WIDTH) + b;
        // Only collect bytes within descriptor boundary [start_addr, start_addr + xfer_len - 1]
        if (byte_addr >= desc.start_addr && byte_addr < (desc.start_addr + desc.xfer_len)) begin
          byte byte_val = (t.data[i] >> (8 * b)) & 8'hFF;
          desc.expected_bytes.push_back(byte_val);
        end
      end
    end
    
    compare_mm2s_data(desc);
  endfunction : write_axi_rd
  
  // Stage 3: Egress Stream Collection & Packet Framing (axis_rd_monitor -> ap)
  virtual function void write_axis_rd(axis_item_type t);
    mm2s_txn_type desc;
    int unsigned pkt_bytes = 0;
    
    if (mm2s_queue.size() == 0) begin
      `uvm_error("SCB_MM2S_UNEXP_STREAM", "Observed egress stream packet on AXIS without active MM2S descriptor!")
      return;
    end
    
    desc = mm2s_queue[0];
    
    // 1. Count packet payload bytes across all beats using TKEEP
    for (int beat = 0; beat < t.data.size(); beat++) begin
      for (int lane = 0; lane < STRB_WIDTH; lane++) begin
        if (t.keep[beat][lane]) begin
          byte act_byte = (t.data[beat] >> (8 * lane)) & 8'hFF;
          desc.actual_bytes.push_back(act_byte);
          pkt_bytes++;
        end
      end
    end
    
    // 2. Check 1-to-1 packet boundary framing per descriptor
    if (desc.packet_count > 0) begin
      `uvm_error("SCB_MM2S_EXTRA_PKT", $sformatf("MM2S descriptor tag 0x%02h produced multiple stream packets! (packet #%0d)", desc.tag, desc.packet_count + 1))
      mm2s_pkt_errors++;
    end
    
    // 3. Verify packet length at TLAST matches descriptor requested length
    if (pkt_bytes != desc.xfer_len) begin
      `uvm_error("SCB_MM2S_PKT_LEN", $sformatf("MM2S Stream packet terminated with TLAST at %0d bytes, but descriptor requested %0d bytes! (tag 0x%02h)", pkt_bytes, desc.xfer_len, desc.tag))
      mm2s_pkt_errors++;
    end
    
    desc.packet_count++;
    desc.stream_pkt_bytes = pkt_bytes;
    desc.stream_done = 1'b1;
    
    compare_mm2s_data(desc);
    
    // If status was already received, both streams are complete -> retire descriptor
    if (desc.status_done) begin
      check_and_retire_mm2s(desc);
    end
  endfunction : write_axis_rd
  
  // Stage 4: Incremental Pair-Wise Comparator
  virtual function void compare_mm2s_data(mm2s_txn_type desc);
    while (desc.expected_bytes.size() > 0 && desc.actual_bytes.size() > 0) begin
      byte exp_b = desc.expected_bytes.pop_front();
      byte act_b = desc.actual_bytes.pop_front();
      mm2s_bytes_checked++;
      
      if (exp_b === act_b) begin
        mm2s_byte_matches++;
        desc.bytes_matched++;
      end
      else begin
        mm2s_byte_mismatches++;
        `uvm_error("SCB_MM2S_DATA_MISMATCH", $sformatf("MM2S Data Mismatch at byte %0d for tag 0x%02h: Expected=0x%02h, Actual=0x%02h", desc.bytes_matched, desc.tag, exp_b, act_b))
      end
    end
  endfunction : compare_mm2s_data
  
  // Stage 5: Status Retirement & Cleanliness Check (dma_rd_desc_monitor -> status_ap)
  virtual function void write_dma_rd_status(dma_desc_item_type t);
    mm2s_txn_type desc;
    mm2s_status_count++;
    
    if (!mm2s_by_tag.exists(t.status_tag)) begin
      `uvm_error("SCB_MM2S_UNEXP_TAG", $sformatf("MM2S Status returned unknown tag: 0x%02h", t.status_tag))
      mm2s_status_mismatches++;
      return;
    end
    
    desc = mm2s_by_tag[t.status_tag];
    desc.status_done = 1'b1;
    desc.status_error = t.status_error;
    
    // Check in-order completion assertion for the single-pipeline MM2S engine
    if (mm2s_queue.size() > 0 && mm2s_queue[0].tag !== t.status_tag) begin
      `uvm_error("SCB_MM2S_OOO", $sformatf("MM2S completion status tag 0x%02h arrived out-of-order! Expected queue head tag 0x%02h", t.status_tag, mm2s_queue[0].tag))
      mm2s_status_mismatches++;
    end
    
    // Temporal Completion Assertion:
    // Status pulse MUST NOT arrive before the egress stream packet has fully retired!
    if (!desc.stream_done) begin
      `uvm_error("SCB_MM2S_EARLY_STATUS", $sformatf("MM2S Descriptor Tag 0x%02h completion status pulsed prematurely at time %0t! Egress stream packet is still draining through FIFO (stream_done=0).", t.status_tag, $time))
      mm2s_status_mismatches++;
    end
    
    // If egress stream packet has already completed, retire descriptor now.
    // If stream packet was still draining, write_axis_rd will retire it once TLAST handshakes.
    if (desc.stream_done) begin
      check_and_retire_mm2s(desc);
    end
  endfunction : write_dma_rd_status
  
  // Retires an MM2S descriptor once BOTH status and stream packet have completed
  virtual function void check_and_retire_mm2s(mm2s_txn_type desc);
    int found_idx = -1;
    
    // 1. Drain any remaining comparisons
    compare_mm2s_data(desc);
    
    // 2. Check 1-to-1 packet boundary framing per descriptor
    if (desc.packet_count != 1) begin
      `uvm_error("SCB_MM2S_PKT_COUNT", $sformatf("MM2S descriptor tag 0x%02h expected 1 stream packet, but saw %0d!", desc.tag, desc.packet_count))
      mm2s_pkt_errors++;
    end
    
    // 3. Verify total byte count matched descriptor transfer length
    if (desc.bytes_matched != desc.xfer_len) begin
      `uvm_error("SCB_MM2S_LEN_MISMATCH", $sformatf("MM2S Length mismatch for tag 0x%02h: Expected=%0d bytes, Verified=%0d bytes", desc.tag, desc.xfer_len, desc.bytes_matched))
      mm2s_status_mismatches++;
    end
    
    // 4. Verify no leftover unmatched bytes
    if (desc.expected_bytes.size() != 0) begin
      `uvm_error("SCB_MM2S_ORPHAN_EXP", $sformatf("MM2S Tag 0x%02h completed with %0d unconsumed expected bytes!", desc.tag, desc.expected_bytes.size()))
      mm2s_status_mismatches++;
    end
    if (desc.actual_bytes.size() != 0) begin
      `uvm_error("SCB_MM2S_ORPHAN_ACT", $sformatf("MM2S Tag 0x%02h completed with %0d uncompared actual stream bytes!", desc.tag, desc.actual_bytes.size()))
      mm2s_status_mismatches++;
    end
    
    // 5. Verify completion status error code
    if (desc.status_error != DMA_ERR_NONE) begin
      `uvm_error("SCB_MM2S_ERR", $sformatf("MM2S Descriptor tag 0x%02h completed with error code: %s (0x%0x)", desc.tag, desc.status_error.name(), desc.status_error))
      mm2s_status_mismatches++;
    end
    
    // 6. Clean up completed descriptor by tag across both lookup structures
    foreach (mm2s_queue[i]) begin
      if (mm2s_queue[i].tag == desc.tag) begin
        found_idx = i;
        break;
      end
    end
    if (found_idx >= 0) begin
      mm2s_queue.delete(found_idx);
    end
    mm2s_by_tag.delete(desc.tag);
    
    `uvm_info("SCB_MM2S_PASS", $sformatf("MM2S Transfer Complete & Verified: tag=0x%02h, len=%0d bytes", desc.tag, desc.bytes_matched), UVM_LOW)
  endfunction : check_and_retire_mm2s
  
  // Stage 1 (S2MM): Write Command Registration (dma_wr_desc_monitor -> cmd_ap)
  virtual function void write_dma_wr_cmd(dma_desc_item_type t);
    s2mm_txn_type desc;
    s2mm_cmd_count++;
    
    // 1. Check for duplicate outstanding tag
    if (s2mm_by_tag.exists(t.tag)) begin
      `uvm_error("SCB_S2MM_DUP_TAG", $sformatf("Duplicate S2MM command tag detected: tag 0x%02h is already pending completion!", t.tag))
      s2mm_status_mismatches++;
      return;
    end
    
    // 2. Legality assertions on descriptor parameters
    if (t.len == 0) begin
      `uvm_error("SCB_S2MM_ZERO_LEN", $sformatf("S2MM descriptor tag 0x%02h requested illegal 0-byte buffer length!", t.tag))
      s2mm_status_mismatches++;
    end
    if ((t.addr + t.len) > (1 << ADDR_WIDTH)) begin
      `uvm_error("SCB_S2MM_ADDR_WRAP", $sformatf("S2MM descriptor tag 0x%02h buffer exceeds memory bounds: addr=0x%04h, len=%0d bytes", t.tag, t.addr, t.len))
      s2mm_addr_errors++;
    end
    
    // 3. Instantiate and initialize tracking object
    desc = new();
    desc.dest_addr = t.addr;
    desc.buffer_len = t.len;
    desc.tag = t.tag;
    desc.expected_next_awaddr = t.addr;
    desc.cmd_seen = 1'b1;
    
    // 4. Pair with early stream packet if waiting in unmatched queue (Data-First Skew handling)
    if (unmatched_axis_pkts.size() > 0) begin
      axis_item_type early_pkt = unmatched_axis_pkts.pop_front();
      `uvm_info("SCB_S2MM_PAIR", $sformatf("Pairing S2MM Descriptor tag 0x%02h with pre-buffered ingress stream packet (%0d beats)", t.tag, early_pkt.data.size()), UVM_MEDIUM)
      bind_stream_to_desc(desc, early_pkt);
    end
    
    s2mm_queue.push_back(desc);
    s2mm_by_tag[t.tag] = desc;
    
    `uvm_info("SCB_S2MM_CMD", $sformatf("Registered S2MM Write Descriptor: tag=0x%02h, dest_addr=0x%04h, buffer_len=%0d bytes", t.tag, t.addr, t.len), UVM_MEDIUM)
  endfunction : write_dma_wr_cmd
  
  // Helper to unpack golden bytes from an ingress stream packet into an S2MM descriptor
  virtual function void bind_stream_to_desc(s2mm_txn_type desc, axis_item_type t);
    int unsigned pkt_bytes = 0;
    
    for (int beat = 0; beat < t.data.size(); beat++) begin
      for (int lane = 0; lane < STRB_WIDTH; lane++) begin
        if (t.keep[beat][lane]) begin
          byte act_byte = (t.data[beat] >> (8 * lane)) & 8'hFF;
          desc.expected_bytes.push_back(act_byte);
          pkt_bytes++;
        end
      end
    end
    
    desc.total_stream_bytes = pkt_bytes;
    desc.stream_done = 1'b1;
    
    // Classify stream payload relative to buffer capacity
    if (pkt_bytes < desc.buffer_len) begin
      desc.is_early_termination = 1'b1;
      `uvm_info("SCB_S2MM_EARLY_TERM", $sformatf("S2MM Tag 0x%02h: Early stream termination (pkt_bytes=%0d < buffer_len=%0d)", desc.tag, pkt_bytes, desc.buffer_len), UVM_MEDIUM)
    end
    else if (pkt_bytes > desc.buffer_len) begin
      desc.is_excess_data = 1'b1;
      `uvm_info("SCB_S2MM_EXCESS", $sformatf("S2MM Tag 0x%02h: Excess stream data (pkt_bytes=%0d > buffer_len=%0d). Excess will be dropped.", desc.tag, pkt_bytes, desc.buffer_len), UVM_MEDIUM)
    end
  endfunction : bind_stream_to_desc
  
  // Stage 2 (S2MM): Ingress Stream Ingestion (axis_wr_monitor -> ap)
  virtual function void write_axis_wr(axis_item_type t);
    s2mm_txn_type desc;
    int stream_desc_idx;
    s2mm_stream_pkt_count++;
    
    // 1. Sanity check: Non-empty stream packet
    if (t.data.size() == 0) begin
      `uvm_error("SCB_S2MM_EMPTY_STREAM", "Observed ingress stream packet with 0 beats!")
      s2mm_pkt_errors++;
      return;
    end
    
    // 2. Sanity check: Intermediate beats must have full TKEEP
    for (int i = 0; i < t.data.size() - 1; i++) begin
      if (t.keep[i] !== {STRB_WIDTH {1'b1}}) begin
        `uvm_error("SCB_S2MM_SPARSE_STREAM", $sformatf("Illegal sparse ingress stream: beat %0d has TKEEP=0x%0h (must be 0x%0h)", i, t.keep[i], {STRB_WIDTH {1'b1}}))
        s2mm_pkt_errors++;
      end
    end
    
    // 3. Correlate with active S2MM descriptor
    stream_desc_idx = -1;
    foreach (s2mm_queue[i]) begin
      if (!s2mm_queue[i].stream_done) begin
        stream_desc_idx = i;
        break;
      end
    end
    
    if (stream_desc_idx >= 0) begin
      desc = s2mm_queue[stream_desc_idx];
      bind_stream_to_desc(desc, t);
      `uvm_info("SCB_S2MM_STREAM", $sformatf("Ingested stream packet (%0d beats, %0d bytes) for S2MM tag 0x%02h", t.data.size(), desc.total_stream_bytes, desc.tag), UVM_MEDIUM)
      compare_s2mm_data(desc);
      if (desc.status_done) begin
        check_and_retire_s2mm(desc);
      end
    end
    else begin
      // Data-First Skew (S2MM_10): Stream arrives before descriptor command
      unmatched_axis_pkts.push_back(t);
      `uvm_info("SCB_S2MM_STREAM_PENDING", $sformatf("Buffered ingress stream packet (%0d beats) awaiting S2MM descriptor", t.data.size()), UVM_MEDIUM)
    end
  endfunction : write_axis_wr
  
  // Stage 3 (S2MM): Memory Write Burst Progression (axi_wr_monitor -> ap)
  virtual function void write_axi_wr(axi_item_type t);
    s2mm_txn_type desc;
    int burst_desc_idx;
    s2mm_burst_count++;
    
    // 1. Sanity check: Ensure an active S2MM descriptor is pending
    if (s2mm_queue.size() == 0) begin
      `uvm_error("SCB_S2MM_UNEXP_BURST", $sformatf("Observed unexpected AXI Write burst (AWADDR=0x%04h, AWLEN=%0d) with no pending S2MM descriptor!", t.addr, t.len))
      s2mm_status_mismatches++;
      return;
    end
    
    // Correlate with the active in-flight descriptor:
    // First match by destination address window to support out-of-order burst interleaving
    burst_desc_idx = -1;
    foreach (s2mm_queue[i]) begin
      bit [ADDR_WIDTH-1:0] aligned_base = s2mm_queue[i].dest_addr & ~(STRB_WIDTH - 1);
      int unsigned exp_b = s2mm_queue[i].is_early_termination ? s2mm_queue[i].total_stream_bytes : s2mm_queue[i].buffer_len;
      if ((t.addr >= aligned_base) && (t.addr < (s2mm_queue[i].dest_addr + exp_b)) && (s2mm_queue[i].total_written_bytes < exp_b)) begin
        burst_desc_idx = i;
        break;
      end
    end

    // Fallback: Select first in-flight descriptor expecting write bursts
    if (burst_desc_idx < 0) begin
      foreach (s2mm_queue[i]) begin
        int unsigned exp_b = s2mm_queue[i].is_early_termination ? s2mm_queue[i].total_stream_bytes : s2mm_queue[i].buffer_len;
        if (s2mm_queue[i].total_written_bytes < exp_b) begin
          burst_desc_idx = i;
          break;
        end
      end
    end

    if (burst_desc_idx >= 0) begin
      desc = s2mm_queue[burst_desc_idx];
    end
    else begin
      desc = s2mm_queue[0];
    end
    
    // 2. Verify AXI Write address progression across multi-bursts
    if (t.addr !== desc.expected_next_awaddr) begin
      `uvm_error("SCB_S2MM_BURST_ADDR", $sformatf("S2MM AXI Write burst address mismatch for tag 0x%02h! Expected=0x%04h, Actual=0x%04h", desc.tag, desc.expected_next_awaddr, t.addr))
      s2mm_addr_errors++;
    end
    
    // 3. 4KB boundary crossing check (AXI4 Section A3.4.1)
    if (((t.addr & 12'hFFF) + ((t.len + 1) * STRB_WIDTH)) > 4096) begin
      `uvm_error("SCB_S2MM_4KB_CROSS", $sformatf("S2MM AXI Write burst crosses 4KB boundary: AWADDR=0x%04h, AWLEN=%0d", t.addr, t.len))
      s2mm_addr_errors++;
    end
    
    // 4. Maximum burst length check (DMA architecture limits to 16 beats)
    if (t.len > 15) begin
      `uvm_error("SCB_S2MM_AWLEN_OVERFLOW", $sformatf("S2MM AXI Write burst exceeds 16-beat limit: AWLEN=%0d", t.len))
      s2mm_addr_errors++;
    end
    
    // 5. Verify slave write response
    if (t.bresp !== AXI_RESP_OKAY) begin
      `uvm_error("SCB_S2MM_BRESP_ERR", $sformatf("S2MM AXI Write burst for tag 0x%02h returned non-OKAY response: 0x%0h", desc.tag, t.bresp))
      s2mm_status_mismatches++;
    end
    
    // Update expected address for next burst
    desc.expected_next_awaddr = t.addr + ((t.len + 1) * STRB_WIDTH);
    
    // 6. Extract actual data bytes qualified by WSTRB
    for (int i = 0; i <= t.len; i++) begin
      for (int b = 0; b < STRB_WIDTH; b++) begin
        if (t.strb[i][b]) begin
          byte act_byte = (t.data[i] >> (8 * b)) & 8'hFF;
          desc.actual_bytes.push_back(act_byte);
          desc.total_written_bytes++;
        end
      end
    end
    
    `uvm_info("SCB_S2MM_BURST", $sformatf("Captured AXI Write burst for tag 0x%02h: AWADDR=0x%04h, AWLEN=%0d, written_bytes=%0d/%0d", desc.tag, t.addr, t.len, desc.total_written_bytes, desc.buffer_len), UVM_MEDIUM)
    
    // Trigger real-time lockstep comparison against ingress stream bytes
    compare_s2mm_data(desc);
    
    // Check if descriptor completion conditions are met
    if (desc.status_done) begin
      check_and_retire_s2mm(desc);
    end
  endfunction : write_axi_wr
  
  // Stage 4 (S2MM): Pair-Wise Incremental Stream-to-Memory Data Comparator
  virtual function void compare_s2mm_data(s2mm_txn_type desc);
    byte exp_b, act_b;
    
    while ((desc.expected_bytes.size() > 0) && (desc.actual_bytes.size() > 0)) begin
      exp_b = desc.expected_bytes.pop_front();
      act_b = desc.actual_bytes.pop_front();
      s2mm_bytes_checked++;
      
      if (exp_b === act_b) begin
        desc.bytes_matched++;
        s2mm_byte_matches++;
      end
      else begin
        `uvm_error("SCB_S2MM_DATA_MISMATCH", $sformatf("S2MM Data Mismatch at byte %0d for tag 0x%02h! Expected(Stream)=0x%02h, Actual(Memory)=0x%02h", desc.bytes_matched, desc.tag, exp_b, act_b))
        s2mm_byte_mismatches++;
      end
    end
  endfunction : compare_s2mm_data
  
  // Stage 5 (S2MM): Write Status Retirement (dma_wr_desc_monitor -> status_ap)
  virtual function void write_dma_wr_status(dma_desc_item_type t);
    s2mm_txn_type desc;
    s2mm_status_count++;
    
    if (!s2mm_by_tag.exists(t.status_tag)) begin
      `uvm_error("SCB_S2MM_UNEXP_STATUS", $sformatf("Observed unexpected S2MM Write Status for tag 0x%02h not in flight!", t.status_tag))
      s2mm_status_mismatches++;
      return;
    end
    
    desc = s2mm_by_tag[t.status_tag];
    
    if (desc.status_done) begin
      `uvm_error("SCB_S2MM_DUP_STATUS", $sformatf("Duplicate S2MM Write Status detected for tag 0x%02h!", t.status_tag))
      s2mm_status_mismatches++;
      return;
    end
    
    desc.status_done = 1'b1;
    desc.status_len = t.status_len;
    desc.status_error = t.status_error;
    
    `uvm_info("SCB_S2MM_STATUS", $sformatf("Received S2MM Write Status: tag=0x%02h, len=%0d bytes, err=%s", t.status_tag, t.status_len, t.status_error.name()), UVM_MEDIUM)
    
    check_and_retire_s2mm(desc);
  endfunction : write_dma_wr_status
  
  // S2MM Retirement & Cleanliness Verification
  virtual function void check_and_retire_s2mm(s2mm_txn_type desc);
    int found_idx = -1;
    int unsigned exp_written_bytes;
    
    // Determine expected written bytes based on buffer capacity vs stream payload
    if (desc.is_early_termination) begin
      exp_written_bytes = desc.total_stream_bytes;
    end
    else begin
      exp_written_bytes = desc.buffer_len;
    end
    
    // Do not retire until all write bursts, stream packet, and the descriptor status handshake are complete
    if (!desc.cmd_seen || !desc.status_done || !desc.stream_done || (desc.total_written_bytes < exp_written_bytes)) begin
      return;
    end
    
    // Run final comparison drain
    compare_s2mm_data(desc);
    
    // 1. Verify byte count matched expectations
    if (desc.bytes_matched != exp_written_bytes) begin
      `uvm_error("SCB_S2MM_LEN_MISMATCH", $sformatf("S2MM Length mismatch for tag 0x%02h: Expected=%0d bytes, Matched=%0d bytes (Written=%0d)", desc.tag, exp_written_bytes, desc.bytes_matched, desc.total_written_bytes))
      s2mm_status_mismatches++;
    end
    
    // 2. Verify status reported transfer length
    if (desc.status_len != exp_written_bytes) begin
      `uvm_error("SCB_S2MM_STAT_LEN_MISMATCH", $sformatf("S2MM Status len mismatch for tag 0x%02h: Expected=%0d bytes, Status reported=%0d bytes", desc.tag, exp_written_bytes, desc.status_len))
      s2mm_status_mismatches++;
    end
    
    // 3. Verify status error code
    if (desc.status_error != DMA_ERR_NONE) begin
      `uvm_error("SCB_S2MM_STATUS_ERR", $sformatf("S2MM Descriptor tag 0x%02h completed with error code: %s", desc.tag, desc.status_error.name()))
      s2mm_status_mismatches++;
    end
    
    // 4. Handle excess stream data (S2MM_08): DUT drops excess beats after buffer_len is written
    if (desc.is_excess_data) begin
      int unsigned dropped_bytes = desc.expected_bytes.size();
      `uvm_info("SCB_S2MM_DROP_CHECK", $sformatf("S2MM Tag 0x%02h: Verified %0d excess stream bytes were cleanly dropped without memory corruption", desc.tag, dropped_bytes), UVM_LOW)
      desc.expected_bytes.delete();
    end
    
    // 5. Verify no orphan uncompared bytes remain
    if (desc.expected_bytes.size() != 0) begin
      `uvm_error("SCB_S2MM_ORPHAN_EXP", $sformatf("S2MM Tag 0x%02h completed with %0d unconsumed stream bytes!", desc.tag, desc.expected_bytes.size()))
      s2mm_status_mismatches++;
    end
    if (desc.actual_bytes.size() != 0) begin
      `uvm_error("SCB_S2MM_ORPHAN_ACT", $sformatf("S2MM Tag 0x%02h completed with %0d uncompared actual memory bytes!", desc.tag, desc.actual_bytes.size()))
      s2mm_status_mismatches++;
    end
    
    // 6. Clean up from tracking queues
    foreach (s2mm_queue[i]) begin
      if (s2mm_queue[i].tag == desc.tag) begin
        found_idx = i;
        break;
      end
    end
    if (found_idx >= 0) begin
      s2mm_queue.delete(found_idx);
    end
    
    s2mm_by_tag.delete(desc.tag);
    
    `uvm_info("SCB_S2MM_PASS", $sformatf("S2MM Transfer Complete & Verified: tag=0x%02h, bytes=%0d", desc.tag, desc.bytes_matched), UVM_LOW)
  endfunction : check_and_retire_s2mm
  
  // End-of-Test Cleanliness Check
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    
    mm2s_hang_count = mm2s_queue.size();
    s2mm_hang_count = s2mm_queue.size();
    
    if (mm2s_hang_count != 0) begin
      `uvm_error("SCB_MM2S_HANG", $sformatf("End of Test Cleanliness: %0d MM2S descriptor(s) never completed! Head tag=0x%02h (stream_done=%0b, status_done=%0b)", mm2s_hang_count, mm2s_queue[0].tag, mm2s_queue[0].stream_done, mm2s_queue[0].status_done))
    end
    
    if (s2mm_hang_count != 0) begin
      `uvm_error("SCB_S2MM_HANG", $sformatf("End of Test Cleanliness: %0d S2MM descriptor(s) never completed! Head tag=0x%02h (stream_done=%0b, status_done=%0b)", s2mm_hang_count, s2mm_queue[0].tag, s2mm_queue[0].stream_done, s2mm_queue[0].status_done))
    end
    
    if (unmatched_axis_pkts.size() != 0) begin
      `uvm_error("SCB_S2MM_ORPHAN_PKT", $sformatf("End of Test Cleanliness: %0d ingress stream packet(s) were never paired with an S2MM descriptor!", unmatched_axis_pkts.size()))
      s2mm_pkt_errors++;
    end
  endfunction : check_phase
  
  // Authoritative Scorecard Summary Report
  virtual function void report_phase(uvm_phase phase);
    bit mm2s_errors, s2mm_errors;
    super.report_phase(phase);
    
    mm2s_errors = (mm2s_byte_mismatches > 0) || (mm2s_status_mismatches > 0) || (mm2s_pkt_errors > 0) || (mm2s_addr_errors > 0) || (mm2s_hang_count > 0) || (mm2s_queue.size() > 0) || (mm2s_by_tag.num() > 0);
    
    s2mm_errors = (s2mm_byte_mismatches > 0) || (s2mm_status_mismatches > 0) || (s2mm_pkt_errors > 0) || (s2mm_addr_errors > 0) || (s2mm_hang_count > 0) || (s2mm_queue.size() > 0) || (s2mm_by_tag.num() > 0) || (unmatched_axis_pkts.size() > 0);
    
    if (mm2s_cmd_count > 0) begin
      `uvm_info("SCB_MM2S", "MM2S SCOREBOARD SUMMARY", UVM_LOW)
      `uvm_info("SCB_MM2S", $sformatf("Commands: %0d | Status Done: %0d | Hung: %0d", mm2s_cmd_count, mm2s_status_count, mm2s_hang_count), UVM_LOW)
      `uvm_info("SCB_MM2S", $sformatf("Bytes Checked: %0d | Matches: %0d | Mismatches: %0d", mm2s_bytes_checked, mm2s_byte_matches, mm2s_byte_mismatches), UVM_LOW)
      `uvm_info("SCB_MM2S", $sformatf("Packet Errors: %0d | Addr Errors: %0d | Status Errors: %0d", mm2s_pkt_errors, mm2s_addr_errors, mm2s_status_mismatches), UVM_LOW)
      
      if (!mm2s_errors) begin
        `uvm_info("SCB_MM2S", "VERDICT: [PASSED] MM2S transfer verified successfully.", UVM_LOW)
      end
      else begin
        `uvm_error("SCB_MM2S", "VERDICT: [FAILED] MM2S mismatches, framing errors, or hung transfers detected.")
      end
    end
    
    if (s2mm_cmd_count > 0) begin
      `uvm_info("SCB_S2MM", "S2MM SCOREBOARD SUMMARY", UVM_LOW)
      `uvm_info("SCB_S2MM", $sformatf("Commands: %0d | Status Done: %0d | Hung: %0d", s2mm_cmd_count, s2mm_status_count, s2mm_hang_count), UVM_LOW)
      `uvm_info("SCB_S2MM", $sformatf("Stream Packets: %0d | Write Bursts: %0d", s2mm_stream_pkt_count, s2mm_burst_count), UVM_LOW)
      `uvm_info("SCB_S2MM", $sformatf("Bytes Checked: %0d | Matches: %0d | Mismatches: %0d", s2mm_bytes_checked, s2mm_byte_matches, s2mm_byte_mismatches), UVM_LOW)
      `uvm_info("SCB_S2MM", $sformatf("Packet Errors: %0d | Addr Errors: %0d | Status Errors: %0d", s2mm_pkt_errors, s2mm_addr_errors, s2mm_status_mismatches), UVM_LOW)
      
      if (!s2mm_errors) begin
        `uvm_info("SCB_S2MM", "VERDICT: [PASSED] S2MM transfer verified successfully.", UVM_LOW)
      end
      else begin
        `uvm_error("SCB_S2MM", "VERDICT: [FAILED] S2MM mismatches, framing errors, or hung transfers detected.")
      end
    end
    
    if ((mm2s_cmd_count == 0) && (s2mm_cmd_count == 0)) begin
      `uvm_warning("SCB_TOP", "No MM2S or S2MM commands observed during the test! Verify that monitor analysis ports are connected to scoreboard in dma_subsystem_env.")
    end
  endfunction : report_phase
endclass : dma_scoreboard

`endif // DMA_SCOREBOARD_SV