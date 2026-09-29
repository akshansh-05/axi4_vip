// File: dma_coverage.sv
// Description: Comprehensive, Sign-off Grade Functional Coverage Model for AXI4 DMA Subsystem.
//              Implements full 13-covergroup architecture spanning Tier 1 (Descriptor Control),
//              Tier 2 (AXI-Stream Datapath), Tier 3 (AXI4-MM Master Engine),
//              Tier 4 (Cross-Tier Protocol Correlation), and Tier 5 (Exception / Write Abort).

`ifndef DMA_COVERAGE_SV
`define DMA_COVERAGE_SV

// Declare analysis port implementation suffixes for multi-channel subscriber monitoring
`uvm_analysis_imp_decl(_dma_rd_cmd)
`uvm_analysis_imp_decl(_dma_rd_status)
`uvm_analysis_imp_decl(_dma_wr_cmd)
`uvm_analysis_imp_decl(_dma_wr_status)
`uvm_analysis_imp_decl(_axis_rd)
`uvm_analysis_imp_decl(_axis_wr)
`uvm_analysis_imp_decl(_axi_rd)
`uvm_analysis_imp_decl(_axi_wr)

class dma_coverage #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_subscriber #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_coverage #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH) this_type;
    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)                     item_type;
    typedef axis_seq_item     #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)                               axis_item_type;
    typedef axi_seq_item      #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH)                                            axi_item_type;

    `uvm_component_param_utils(this_type)

    // Analysis Implementation Ports for all 8 passive monitor taps
    uvm_analysis_imp_dma_rd_cmd    #(item_type,      this_type) analysis_imp_dma_rd_cmd;
    uvm_analysis_imp_dma_rd_status #(item_type,      this_type) analysis_imp_dma_rd_status;
    uvm_analysis_imp_dma_wr_cmd    #(item_type,      this_type) analysis_imp_dma_wr_cmd;
    uvm_analysis_imp_dma_wr_status #(item_type,      this_type) analysis_imp_dma_wr_status;
    uvm_analysis_imp_axis_rd       #(axis_item_type, this_type) analysis_imp_axis_rd;
    uvm_analysis_imp_axis_wr       #(axis_item_type, this_type) analysis_imp_axis_wr;
    uvm_analysis_imp_axi_rd        #(axi_item_type,  this_type) analysis_imp_axi_rd;
    uvm_analysis_imp_axi_wr        #(axi_item_type,  this_type) analysis_imp_axi_wr;

    // Latched transaction handles for sampling
    item_type            txn_rd_cmd;
    item_type            txn_rd_status;
    item_type            txn_wr_cmd;
    item_type            txn_wr_status;
    axis_item_type       axis_rd_txn;
    axis_item_type       axis_wr_txn;
    axi_item_type        axi_rd_txn;
    axi_item_type        axi_wr_txn;

    // Intermediate sampling variables for per-beat and cross-tier coverage
    bit [STRB_WIDTH-1:0] current_rd_tkeep;
    bit                  is_rd_last_beat;
    bit [STRB_WIDTH-1:0] current_wr_tkeep;
    int unsigned         current_wr_delay;
    bit                  is_wr_last_beat;

    bit [1:0]            current_rresp;
    bit                  is_rlast;

    bit [STRB_WIDTH-1:0] current_wstrb;
    int                  wr_beat_idx;
    int                  total_wr_beats;
    bit                  is_wlast;

    bit                  is_write_aborted;
    bit [LEN_WIDTH-1:0]  abort_bytes_transferred;
    dma_error_e          abort_status_error;

    bit [1:0]            cross_desc_align;
    int                  cross_desc_len_cat;
    bit                  cross_page_span;
    int                  cross_status_cat;
    bit                  cross_direction; // 0: Read (MM2S), 1: Write (S2MM)

    // =========================================================================
    // COVERGROUP 1: DMA Read Descriptor Channel (Command) [Tier 1]
    // Sampling Event: Sampled on accepted Read Descriptor command (valid && ready)
    // =========================================================================
    covergroup cg_dma_rd_desc;
        option.per_instance = 1;
        option.name         = "cg_dma_rd_desc";

        // Coverpoint 1.1: Address Alignment within 32-bit beat (strobe & shift logic)
        cp_addr_align : coverpoint txn_rd_cmd.addr[1:0] {
            bins word_aligned    = {2'b00}; // Starts at Byte 0 (aligned word)
            bins unaligned_byte1 = {2'b01}; // Starts at Byte 1 (+1 byte offset)
            bins halfword_align  = {2'b10}; // Starts at Byte 2 (+2 bytes offset)
            bins unaligned_byte3 = {2'b11}; // Starts at Byte 3 (+3 bytes offset)
        }

        // Coverpoint 1.2: Address Space & Extreme Boundary Coverage (64 KB)
        cp_addr_range : coverpoint txn_rd_cmd.addr {
            bins min_addr     = {16'h0000};                // Absolute lowest address
            bins low_range    = {[16'h0001 : 16'h3FFF]};   // Lower 16 KB
            bins mid_range    = {[16'h4000 : 16'hBFFF]};   // Central 32 KB general region
            bins high_range   = {[16'hC000 : 16'hFFEF]};   // Upper 16 KB
            bins max_boundary = {[16'hFFF0 : 16'hFFFF]};   // Extreme top boundary (16-byte edge)
        }

        // Coverpoint 1.3: Start Offset within 4KB Page (bits [11:0])
        cp_page_offset : coverpoint txn_rd_cmd.addr[11:0] {
            bins page_start      = {12'h000};             // Exactly at page boundary
            bins page_lower_half = {[12'h001 : 12'h7FF]}; // Lower 2KB
            bins page_upper_half = {[12'h800 : 12'hFBF]}; // Upper 2KB
            bins near_page_end   = {[12'hFC0 : 12'hFFF]}; // Within 64 bytes of 4KB edge
        }

        // Coverpoint 1.4: Transfer Length in Bytes
        cp_transfer_len : coverpoint txn_rd_cmd.len {
            bins len_1_byte      = {1};              // Absolute minimum transfer
            bins len_sub_word    = {[2 : 3]};        // Partial 1-word transfer
            bins len_1_word      = {4};              // Exactly 1 beat (4 bytes)
            bins len_short_burst = {[5 : 63]};       // Single AXI burst (2 to 15 beats)
            bins len_single_max  = {64};             // Exact max AXI burst (16 beats)
            bins len_multi_burst = {[65 : 4095]};    // Multiple bursts within 4KB
            bins len_4kb_exact   = {4096};           // Exact 4KB page
            bins len_large_page  = {[4097 : 65535]}; // Spanning across multiple pages
        }

        // Coverpoint 1.5: Transaction Tag (TAG_WIDTH = 8)
        cp_desc_tag : coverpoint txn_rd_cmd.tag {
            bins tag_zero = {8'h00};             // Default zero tag
            bins tag_low  = {[8'h01 : 8'h0F]};   // Tags 1 to 15
            bins tag_mid  = {[8'h10 : 8'hEF]};   // Tags 16 to 239
            bins tag_high = {[8'hF0 : 8'hFF]};   // Upper boundary tags
        }

        // Cross Coverage 1: Alignment x Transfer Length
        cross_addr_align_x_len : cross cp_addr_align, cp_transfer_len;

        // Cross Coverage 2: 4KB Page Offset x Transfer Length
        cross_page_offset_x_len : cross cp_page_offset, cp_transfer_len;

    endgroup : cg_dma_rd_desc

    // =========================================================================
    // COVERGROUP 2: DMA Read Descriptor Status Channel [Tier 1]
    // Sampling Event: Sampled on Read Descriptor Completion Status (read_desc_status_valid)
    // =========================================================================
    covergroup cg_dma_rd_desc_status;
        option.per_instance = 1;
        option.name         = "cg_dma_rd_desc_status";

        // Coverpoint 2.1: Read Completion Error Status Code
        cp_status_error : coverpoint txn_rd_status.status_error {
            bins err_none   = {DMA_ERR_NONE};          // 4'd0: Normal successful completion
            bins err_slverr = {DMA_ERR_AXI_RD_SLVERR}; // 4'd4: R channel Slave Error
            bins err_decerr = {DMA_ERR_AXI_RD_DECERR}; // 4'd5: R channel Decode Error
            illegal_bins err_wr_codes = {DMA_ERR_AXI_WR_SLVERR, DMA_ERR_AXI_WR_DECERR};
        }

        // Coverpoint 2.2: Returned Completion Tag
        cp_status_tag : coverpoint txn_rd_status.status_tag {
            bins tag_zero = {8'h00};             // Default zero tag
            bins tag_low  = {[8'h01 : 8'h0F]};   // Tags 1 to 15
            bins tag_mid  = {[8'h10 : 8'hEF]};   // Tags 16 to 239
            bins tag_high = {[8'hF0 : 8'hFF]};   // Upper boundary tags
        }

    endgroup : cg_dma_rd_desc_status

    // =========================================================================
    // COVERGROUP 3: DMA Write Descriptor Channel (Command) [Tier 1]
    // Sampling Event: Sampled on accepted Write Descriptor command (valid && ready)
    // =========================================================================
    covergroup cg_dma_wr_desc;
        option.per_instance = 1;
        option.name         = "cg_dma_wr_desc";

        // Coverpoint 3.1: Write Address Alignment (tests WSTRB masking on first beat)
        cp_wr_addr_align : coverpoint txn_wr_cmd.addr[1:0] {
            bins word_aligned    = {2'b00}; // Starts at Byte 0 (WSTRB = 4'b1111)
            bins unaligned_byte1 = {2'b01}; // Starts at Byte 1 (WSTRB = 4'b1110)
            bins halfword_align  = {2'b10}; // Starts at Byte 2 (WSTRB = 4'b1100)
            bins unaligned_byte3 = {2'b11}; // Starts at Byte 3 (WSTRB = 4'b1000)
        }

        // Coverpoint 3.2: Write Address Range (64 KB)
        cp_wr_addr_range : coverpoint txn_wr_cmd.addr {
            bins min_addr     = {16'h0000};                // Absolute lowest address
            bins low_range    = {[16'h0001 : 16'h3FFF]};   // Lower 16 KB
            bins mid_range    = {[16'h4000 : 16'hBFFF]};   // Central 32 KB general region
            bins high_range   = {[16'hC000 : 16'hFFEF]};   // Upper 16 KB
            bins max_boundary = {[16'hFFF0 : 16'hFFFF]};   // Extreme top boundary (16-byte edge)
        }

        // Coverpoint 3.3: Write Start Offset within 4KB Page (bits [11:0])
        cp_wr_page_offset : coverpoint txn_wr_cmd.addr[11:0] {
            bins page_start      = {12'h000};             // Exactly at page boundary
            bins page_lower_half = {[12'h001 : 12'h7FF]}; // Lower 2KB
            bins page_upper_half = {[12'h800 : 12'hFBF]}; // Upper 2KB
            bins near_page_end   = {[12'hFC0 : 12'hFFF]}; // Within 64 bytes of 4KB edge
        }

        // Coverpoint 3.4: Write Buffer Capacity Length in Bytes
        cp_wr_buffer_len : coverpoint txn_wr_cmd.len {
            bins len_1_byte      = {1};              // Single byte buffer
            bins len_sub_word    = {[2 : 3]};        // Partial 1-word buffer
            bins len_1_word      = {4};              // Exactly 1 beat (4 bytes)
            bins len_short_burst = {[5 : 63]};       // Single AXI burst (2 to 15 beats)
            bins len_single_max  = {64};             // Exact max AXI burst (16 beats)
            bins len_multi_burst = {[65 : 4095]};    // Multiple bursts within 4KB
            bins len_4kb_exact   = {4096};           // Exact 4KB page
            bins len_large_page  = {[4097 : 65535]}; // Multi-page buffer
        }

        // Coverpoint 3.5: Write Transaction Tag
        cp_wr_desc_tag : coverpoint txn_wr_cmd.tag {
            bins tag_zero = {8'h00};             // Default zero tag
            bins tag_low  = {[8'h01 : 8'h0F]};   // Tags 1 to 15
            bins tag_mid  = {[8'h10 : 8'hEF]};   // Tags 16 to 239
            bins tag_high = {[8'hF0 : 8'hFF]};   // Upper boundary tags
        }

        // Cross Coverage 1: Write Alignment x Buffer Length
        cross_wr_align_x_len : cross cp_wr_addr_align, cp_wr_buffer_len;

        // Cross Coverage 2: Write 4KB Page Offset x Buffer Length
        cross_wr_page_x_len  : cross cp_wr_page_offset, cp_wr_buffer_len;

    endgroup : cg_dma_wr_desc

    // =========================================================================
    // COVERGROUP 4: DMA Write Descriptor Status Channel [Tier 1]
    // Sampling Event: Sampled on Write Descriptor Completion Status (write_desc_status_valid)
    // =========================================================================
    covergroup cg_dma_wr_desc_status;
        option.per_instance = 1;
        option.name         = "cg_dma_wr_desc_status";

        // Coverpoint 4.1: Write Completion Error Status Code
        cp_wr_status_error : coverpoint txn_wr_status.status_error {
            bins err_none   = {DMA_ERR_NONE};          // 4'd0: Normal successful write
            bins err_slverr = {DMA_ERR_AXI_WR_SLVERR}; // 4'd6: B channel Slave Error
            bins err_decerr = {DMA_ERR_AXI_WR_DECERR}; // 4'd7: B channel Decode Error
            illegal_bins err_rd_codes = {DMA_ERR_AXI_RD_SLVERR, DMA_ERR_AXI_RD_DECERR};
        }

        // Coverpoint 4.2: Actual Written Bytes vs Buffer Capacity Fidelity
        cp_wr_len_fidelity : coverpoint (
            (txn_wr_status.status_len == txn_wr_status.len) ? 2 :
            ((txn_wr_status.status_len < txn_wr_status.len) && (txn_wr_status.status_len > 0)) ? 1 : 0
        ) {
            bins full_buffer_transfer = {2}; // status_len == len (stream filled buffer)
            bins early_stream_tlast   = {1}; // status_len < len  (stream ended early via TLAST)
            bins zero_byte_abort      = {0}; // status_len == 0   (aborted or 0 bytes transferred)
        }

        // Coverpoint 4.3: Returned Write Completion Tag
        cp_wr_status_tag : coverpoint txn_wr_status.status_tag {
            bins tag_zero = {8'h00};             // Default zero tag
            bins tag_low  = {[8'h01 : 8'h0F]};   // Tags 1 to 15
            bins tag_mid  = {[8'h10 : 8'hEF]};   // Tags 16 to 239
            bins tag_high = {[8'hF0 : 8'hFF]};   // Upper boundary tags
        }

    endgroup : cg_dma_wr_desc_status

    // =========================================================================
    // COVERGROUP 5: AXI4-Stream Read Data Channel (Egress Stream from DUT) [Tier 2]
    // Sampling Event: Sampled on accepted stream beats (m_axis_read_data_tvalid && tready)
    // =========================================================================
    covergroup cg_axis_rd_stream;
        option.per_instance = 1;
        option.name         = "cg_axis_rd_stream";

        // Coverpoint 5.1: Stream Byte Qualifiers on Last Beat (TKEEP)
        cp_rd_last_tkeep : coverpoint current_rd_tkeep iff (is_rd_last_beat) {
            bins full_word    = {4'b1111}; // 4 active bytes (aligned word end)
            bins three_bytes  = {4'b0111}; // 3 active bytes (unaligned length)
            bins two_bytes    = {4'b0011}; // 2 active bytes (half-word end)
            bins single_byte  = {4'b0001}; // 1 active byte (odd byte length)
            illegal_bins zero = {4'b0000}; // Illegal in AXI-Stream for valid beat
        }

        // Coverpoint 5.2: Egress Packet Size in Beats
        cp_rd_packet_beats : coverpoint axis_rd_txn.data.size() {
            bins single_beat = {1};              // 1-beat packet (TLAST on beat 0)
            bins short_pkt   = {[2 : 15]};       // Less than 1 AXI burst (<64B)
            bins burst_16    = {16};             // Exactly 1 AXI burst (64B)
            bins med_pkt     = {[17 : 64]};      // Multi-burst packet
            bins long_pkt    = {[65 : 256]};     // Large packet
        }

        // Coverpoint 5.3: Downstream Receiver Backpressure Delays
        cp_rd_backpressure : coverpoint axis_rd_txn.ready_delay {
            bins zero_delay   = {0};             // Full speed (TREADY held high)
            bins short_stall  = {[1 : 3]};       // 1-3 cycle pauses
            bins med_stall    = {[4 : 10]};      // Moderate backpressure
            bins heavy_stall  = {[11 : 30]};     // Heavy backpressure (stresses internal FIFO)
        }

        // Cross Coverage: Packet Length x Last Beat Byte Mask
        cross_rd_pkt_len_x_last_tkeep : cross cp_rd_packet_beats, cp_rd_last_tkeep;

    endgroup : cg_axis_rd_stream

    // =========================================================================
    // COVERGROUP 6: AXI4-Stream Write Data Channel (Ingress Stream to DUT) [Tier 2]
    // Sampling Event: Sampled on accepted stream beats (s_axis_write_data_tvalid && tready)
    // =========================================================================
    covergroup cg_axis_wr_stream;
        option.per_instance = 1;
        option.name         = "cg_axis_wr_stream";

        // Coverpoint 6.1: Ingress Byte Qualifiers on Last Beat (TKEEP)
        cp_wr_last_tkeep : coverpoint current_wr_tkeep iff (is_wr_last_beat) {
            bins full_word    = {4'b1111}; // 4 active bytes
            bins three_bytes  = {4'b0111}; // 3 active bytes
            bins two_bytes    = {4'b0011}; // 2 active bytes
            bins single_byte  = {4'b0001}; // 1 active byte
            illegal_bins zero = {4'b0000}; // Illegal in AXI-Stream for valid beat
        }

        // Coverpoint 6.2: Ingress Packet Size in Beats
        cp_wr_packet_beats : coverpoint axis_wr_txn.data.size() {
            bins single_beat = {1};              // 1-beat packet (TLAST on beat 0)
            bins short_pkt   = {[2 : 15]};       // Less than 1 AXI burst (<64B)
            bins burst_16    = {16};             // Exactly 1 AXI burst (64B)
            bins med_pkt     = {[17 : 64]};      // Multi-burst packet
            bins long_pkt    = {[65 : 256]};     // Large packet
        }

        // Coverpoint 6.3: Upstream Transmitter Inter-Beat Injection Delays
        cp_wr_inter_beat_delay : coverpoint current_wr_delay {
            bins back_to_back = {0};             // Consecutive beats (0 cycle bubble)
            bins short_pause  = {[1 : 3]};       // 1-3 cycle pause between beats
            bins med_pause    = {[4 : 10]};      // Moderate producer pacing
            bins long_pause   = {[11 : 30]};     // Sparse stream transmission
        }

        // Cross Coverage: Ingress Packet Length x Last Beat Byte Mask
        cross_wr_pkt_len_x_last_tkeep : cross cp_wr_packet_beats, cp_wr_last_tkeep;

    endgroup : cg_axis_wr_stream

    // =========================================================================
    // COVERGROUP 7: DMA AXI-MM Read Address Channel (AR Master) [Tier 3]
    // Sampling Event: Sampled on AXI Read Address handshake (m_axi_arvalid && arready)
    // =========================================================================
    covergroup cg_dma_axi_ar_master;
        option.per_instance = 1;
        option.name         = "cg_dma_axi_ar_master";

        // Coverpoint 7.1: AXI Read Burst Length (ARLEN: 0 to 15, beats = len + 1)
        cp_ar_len : coverpoint axi_rd_txn.len {
            bins single_beat = {0};                  // 1 beat transfer (ARLEN=0)
            bins short_burst = {[1 : 14]};           // 2 to 15 beats
            bins max_burst   = {15};                 // 16 beats (AXI_MAX_BURST_LEN = 16 limit)
            illegal_bins exceeds_dma_burst = {[16 : 255]}; // DMA must never exceed max burst len
        }

        // Coverpoint 7.2: AXI Read Transfer Size (ARSIZE: 32-bit bus width = 4B)
        cp_ar_size : coverpoint axi_rd_txn.size {
            bins size_4B = {3'b010};                 // Full 32-bit width (4 bytes per beat)
            illegal_bins narrow_or_oversize = {3'b000, 3'b001, [3'b011 : 3'b111]};
        }

        // Coverpoint 7.3: AXI Read Burst Type (ARBURST: INCR only)
        cp_ar_burst : coverpoint axi_rd_txn.burst {
            bins burst_incr = {AXI_BURST_INCR};      // Sequential INCR burst
            illegal_bins non_incr = {AXI_BURST_FIXED, AXI_BURST_WRAP, AXI_BURST_RSVD};
        }

        // Coverpoint 7.4: AXI Read Address Alignment (ARADDR[1:0])
        cp_ar_addr_align : coverpoint axi_rd_txn.addr[1:0] {
            bins word_aligned    = {2'b00};          // 4-byte word aligned
            bins unaligned_byte1 = {2'b01};          // +1 byte offset
            bins halfword_align  = {2'b10};          // +2 bytes offset
            bins unaligned_byte3 = {2'b11};          // +3 bytes offset
        }

        // Coverpoint 7.5: 4KB Page Offset (ARADDR[11:0])
        cp_ar_page_offset : coverpoint axi_rd_txn.addr[11:0] {
            bins page_start      = {12'h000};
            bins page_lower_half = {[12'h001 : 12'h7FF]};
            bins page_upper_half = {[12'h800 : 12'hFBF]};
            bins near_page_end   = {[12'hFC0 : 12'hFFF]}; // Edge of 4KB boundary
        }

        // Coverpoint 7.6: Strict 4KB Boundary Adherence
        cp_ar_4kb_boundary : coverpoint (
            ((axi_rd_txn.addr[11:0] + ((axi_rd_txn.len + 1) * 4)) <= 4096) ? 1 : 0
        ) {
            bins fits_in_4kb_page        = {1};
            illegal_bins crosses_4kb_page = {0}; // Hardware must split before crossing!
        }

        // Cross Coverage: Address Alignment x Burst Length
        cross_ar_align_x_len : cross cp_ar_addr_align, cp_ar_len;

        // Cross Coverage: 4KB Page Offset x Burst Length
        cross_ar_offset_x_len : cross cp_ar_page_offset, cp_ar_len;

    endgroup : cg_dma_axi_ar_master

    // =========================================================================
    // COVERGROUP 8: DMA AXI-MM Read Data Channel (R Master) [Tier 3]
    // Sampling Event: Sampled on each accepted read data beat (m_axi_rvalid && rready)
    // =========================================================================
    covergroup cg_dma_axi_r_master;
        option.per_instance = 1;
        option.name         = "cg_dma_axi_r_master";

        // Coverpoint 8.1: Read Data Response Status (RRESP)
        cp_rresp : coverpoint current_rresp {
            bins resp_okay   = {2'b00};              // Normal success (OKAY)
            bins resp_slverr = {2'b10};              // Slave error
            bins resp_decerr = {2'b11};              // Decode error
            ignore_bins resp_exokay = {2'b01};       // Not applicable to DMA master
        }

        // Coverpoint 8.2: Read Last Beat Flag (RLAST)
        cp_rlast : coverpoint is_rlast {
            bins intermediate_beat = {0};
            bins last_burst_beat   = {1};
        }

        // Cross Coverage: RRESP x RLAST (Slave/Decode errors on intermediate vs final beat)
        cross_rresp_x_rlast : cross cp_rresp, cp_rlast;

    endgroup : cg_dma_axi_r_master

    // =========================================================================
    // COVERGROUP 9: DMA AXI-MM Write Address Channel (AW Master) [Tier 3]
    // Sampling Event: Sampled on AXI Write Address handshake (m_axi_awvalid && awready)
    // =========================================================================
    covergroup cg_dma_axi_aw_master;
        option.per_instance = 1;
        option.name         = "cg_dma_axi_aw_master";

        // Coverpoint 9.1: AXI Write Burst Length (AWLEN: 0 to 15, beats = len + 1)
        cp_aw_len : coverpoint axi_wr_txn.len {
            bins single_beat = {0};                  // 1 beat transfer (AWLEN=0)
            bins short_burst = {[1 : 14]};           // 2 to 15 beats
            bins max_burst   = {15};                 // 16 beats (AXI_MAX_BURST_LEN = 16 limit)
            illegal_bins exceeds_dma_burst = {[16 : 255]}; // DMA must never exceed max burst len
        }

        // Coverpoint 9.2: AXI Write Transfer Size (AWSIZE: 32-bit bus width = 4B)
        cp_aw_size : coverpoint axi_wr_txn.size {
            bins size_4B = {3'b010};                 // Full 32-bit width (4 bytes per beat)
            illegal_bins narrow_or_oversize = {3'b000, 3'b001, [3'b011 : 3'b111]};
        }

        // Coverpoint 9.3: AXI Write Burst Type (AWBURST: INCR only)
        cp_aw_burst : coverpoint axi_wr_txn.burst {
            bins burst_incr = {AXI_BURST_INCR};      // Sequential INCR burst
            illegal_bins non_incr = {AXI_BURST_FIXED, AXI_BURST_WRAP, AXI_BURST_RSVD};
        }

        // Coverpoint 9.4: AXI Write Address Alignment (AWADDR[1:0])
        cp_aw_addr_align : coverpoint axi_wr_txn.addr[1:0] {
            bins word_aligned    = {2'b00};          // 4-byte word aligned
            bins unaligned_byte1 = {2'b01};          // +1 byte offset
            bins halfword_align  = {2'b10};          // +2 bytes offset
            bins unaligned_byte3 = {2'b11};          // +3 bytes offset
        }

        // Coverpoint 9.5: 4KB Page Offset (AWADDR[11:0])
        cp_aw_page_offset : coverpoint axi_wr_txn.addr[11:0] {
            bins page_start      = {12'h000};
            bins page_lower_half = {[12'h001 : 12'h7FF]};
            bins page_upper_half = {[12'h800 : 12'hFBF]};
            bins near_page_end   = {[12'hFC0 : 12'hFFF]}; // Edge of 4KB boundary
        }

        // Coverpoint 9.6: Strict 4KB Boundary Adherence
        cp_aw_4kb_boundary : coverpoint (
            ((axi_wr_txn.addr[11:0] + ((axi_wr_txn.len + 1) * 4)) <= 4096) ? 1 : 0
        ) {
            bins fits_in_4kb_page        = {1};
            illegal_bins crosses_4kb_page = {0}; // Hardware must split before crossing!
        }

        // Cross Coverage: Address Alignment x Burst Length
        cross_aw_align_x_len : cross cp_aw_addr_align, cp_aw_len;

        // Cross Coverage: 4KB Page Offset x Burst Length
        cross_aw_offset_x_len : cross cp_aw_page_offset, cp_aw_len;

    endgroup : cg_dma_axi_aw_master

    // =========================================================================
    // COVERGROUP 10: DMA AXI-MM Write Data Channel (W Master) [Tier 3]
    // Sampling Event: Sampled on each accepted write data beat (m_axi_wvalid && wready)
    // =========================================================================
    covergroup cg_dma_axi_w_master;
        option.per_instance = 1;
        option.name         = "cg_dma_axi_w_master";

        // Coverpoint 10.1: First Beat WSTRB Masking for Unaligned Transfers
        cp_wstrb_first_beat : coverpoint current_wstrb iff (wr_beat_idx == 0) {
            bins strb_aligned = {4'b1111};           // Starts at byte 0 (aligned)
            bins strb_byte1   = {4'b1110};           // Starts at byte 1 (unaligned)
            bins strb_byte2   = {4'b1100};           // Starts at byte 2 (half-word)
            bins strb_byte3   = {4'b1000};           // Starts at byte 3 (unaligned)
        }

        // Coverpoint 10.2: Intermediate Beat WSTRB Full Word Strobes
        cp_wstrb_mid_beats : coverpoint current_wstrb iff (wr_beat_idx > 0 && wr_beat_idx < total_wr_beats - 1) {
            bins strb_full = {4'b1111};              // All bytes active in middle beats
        }

        // Coverpoint 10.3: Last Beat WSTRB Partial Masking for Trailing Bytes
        cp_wstrb_last_beat : coverpoint current_wstrb iff (wr_beat_idx == total_wr_beats - 1) {
            bins full_word      = {4'b1111};         // Full word end
            bins three_bytes    = {4'b0111};         // Ends at byte 2
            bins two_bytes      = {4'b0011};         // Ends at byte 1
            bins single_byte    = {4'b0001};         // Ends at byte 0
            bins partial_mid_1  = {4'b0010, 4'b0100, 4'b1000}; // Sub-word unaligned combinations
            bins partial_mid_2  = {4'b0110, 4'b1100};
            bins partial_mid_3  = {4'b1110};
        }

        // Coverpoint 10.4: Write Last Beat Indicator (WLAST)
        cp_wlast : coverpoint is_wlast {
            bins intermediate_beat = {0};
            bins last_burst_beat   = {1};
        }

    endgroup : cg_dma_axi_w_master

    // =========================================================================
    // COVERGROUP 11: DMA AXI-MM Write Response Channel (B Master) [Tier 3]
    // Sampling Event: Sampled on Write Response handshake (m_axi_bvalid && bready)
    // =========================================================================
    covergroup cg_dma_axi_b_master;
        option.per_instance = 1;
        option.name         = "cg_dma_axi_b_master";

        // Coverpoint 11.1: Write Response Status Code (BRESP)
        cp_bresp : coverpoint axi_wr_txn.bresp {
            bins resp_okay   = {2'b00};              // Normal success (OKAY)
            bins resp_slverr = {2'b10};              // Slave error
            bins resp_decerr = {2'b11};              // Decode error
            ignore_bins resp_exokay = {2'b01};       // Not applicable to DMA master
        }

    endgroup : cg_dma_axi_b_master

    // =========================================================================
    // COVERGROUP 12: DMA Write Abort & Early Termination [Tier 5]
    // Sampling Event: Sampled on Write Descriptor completion status
    // =========================================================================
    covergroup cg_write_abort;
        option.per_instance = 1;
        option.name         = "cg_write_abort";

        // Coverpoint 12.1: Write Termination Condition
        cp_abort_event : coverpoint is_write_aborted {
            bins normal_completion = {0};            // status_len == len, transfer full
            bins transfer_aborted  = {1};            // write_abort triggered or early TLAST
        }

        // Coverpoint 12.2: Error Status under Write Operation
        cp_abort_error : coverpoint abort_status_error {
            bins err_none   = {DMA_ERR_NONE};
            bins err_slverr = {DMA_ERR_AXI_WR_SLVERR};
            bins err_decerr = {DMA_ERR_AXI_WR_DECERR};
        }

        // Coverpoint 12.3: Data Volume Committed Prior to Termination
        cp_abort_byte_count : coverpoint abort_bytes_transferred {
            bins zero_bytes            = {0};            // Immediate abort before any beat
            bins partial_first_burst   = {[1 : 63]};     // Aborted during initial burst
            bins multi_burst_committed = {[64 : 4095]};  // Aborted after 1+ bursts
            bins full_page_committed   = {[4096 : 65535]};
        }

        // Cross Coverage: Abort Event x Error Status
        cross_abort_x_error : cross cp_abort_event, cp_abort_error;

        // Cross Coverage: Abort Event x Bytes Committed
        cross_abort_x_bytes : cross cp_abort_event, cp_abort_byte_count;

    endgroup : cg_write_abort

    // =========================================================================
    // COVERGROUP 13: DMA Cross-Tier Protocol Correlation [Tier 4]
    // Sampling Event: Sampled on completion of Read or Write DMA transfers
    // Correlates Descriptor Attributes -> AXI Burst Splitting -> Completion Status
    // =========================================================================
    covergroup cg_cross_tier;
        option.per_instance = 1;
        option.name         = "cg_cross_tier";

        // Coverpoint 13.1: Start Address Alignment Category
        cp_cross_desc_align : coverpoint cross_desc_align {
            bins aligned     = {2'b00};
            bins unaligned_1 = {2'b01};
            bins unaligned_2 = {2'b10};
            bins unaligned_3 = {2'b11};
        }

        // Coverpoint 13.2: Descriptor Transfer Length Category
        cp_cross_desc_len : coverpoint cross_desc_len_cat {
            bins short_single_burst = {0}; // 1 to 64 bytes (fits in single AXI burst)
            bins med_multi_burst    = {1}; // 65 to 512 bytes (2 to 8 AXI bursts)
            bins large_bursts       = {2}; // 513 to 4096 bytes (multi-burst intra-page)
            bins extreme_multi_page = {3}; // > 4096 bytes (spanning 4KB pages)
        }

        // Coverpoint 13.3: 4KB Boundary Crossing Demand
        cp_cross_page_span : coverpoint cross_page_span {
            bins intra_page = {0};           // Transfer entirely contained within 4KB
            bins spans_4kb  = {1};           // Transfer crosses one or more 4KB boundaries
        }

        // Coverpoint 13.4: Final Transaction Error Status
        cp_cross_status : coverpoint cross_status_cat {
            bins normal_success = {0};       // DMA_ERR_NONE
            bins slave_fault    = {1};       // SLVERR
            bins decode_fault   = {2};       // DECERR
        }

        // Coverpoint 13.5: Transfer Direction Engine
        cp_cross_direction : coverpoint cross_direction {
            bins read_mm2s  = {0};           // Memory-to-Stream Read Engine
            bins write_s2mm = {1};           // Stream-to-Memory Write Engine
        }

        // Cross Coverage 1: Alignment x Length (Ensures all alignments tested at all scales)
        cross_align_x_len : cross cp_cross_desc_align, cp_cross_desc_len;

        // Cross Coverage 2: Alignment x 4KB Boundary Crossing (Stress testing boundary unaligned splits)
        cross_align_x_page_span : cross cp_cross_desc_align, cp_cross_page_span;

        // Cross Coverage 3: Length Scale x 4KB Page Crossing
        cross_len_x_page_span : cross cp_cross_desc_len, cp_cross_page_span;

        // Cross Coverage 4: 4KB Page Crossing x Error Status (Ensure errors handled properly at boundaries)
        cross_page_span_x_status : cross cp_cross_page_span, cp_cross_status;

        // Cross Coverage 5: Direction x Page Crossing x Status
        cross_dir_x_span_x_status : cross cp_cross_direction, cp_cross_page_span, cp_cross_status;

    endgroup : cg_cross_tier

    // =========================================================================
    // Constructor: Instantiate All 13 Covergroups
    // =========================================================================
    function new(string name = "dma_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_dma_rd_desc        = new();
        cg_dma_rd_desc_status = new();
        cg_dma_wr_desc        = new();
        cg_dma_wr_desc_status = new();
        cg_axis_rd_stream     = new();
        cg_axis_wr_stream     = new();
        cg_dma_axi_ar_master  = new();
        cg_dma_axi_r_master   = new();
        cg_dma_axi_aw_master  = new();
        cg_dma_axi_w_master   = new();
        cg_dma_axi_b_master   = new();
        cg_write_abort        = new();
        cg_cross_tier         = new();
    endfunction : new

    // =========================================================================
    // Build Phase: Initialize Analysis Implementation Ports
    // =========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_imp_dma_rd_cmd    = new("analysis_imp_dma_rd_cmd", this);
        analysis_imp_dma_rd_status = new("analysis_imp_dma_rd_status", this);
        analysis_imp_dma_wr_cmd    = new("analysis_imp_dma_wr_cmd", this);
        analysis_imp_dma_wr_status = new("analysis_imp_dma_wr_status", this);
        analysis_imp_axis_rd       = new("analysis_imp_axis_rd", this);
        analysis_imp_axis_wr       = new("analysis_imp_axis_wr", this);
        analysis_imp_axi_rd        = new("analysis_imp_axi_rd", this);
        analysis_imp_axi_wr        = new("analysis_imp_axi_wr", this);
    endfunction : build_phase

    // =========================================================================
    // Default UVM Subscriber Write Method
    // =========================================================================
    virtual function void write(item_type t);
        if (t.trans_type == DESC_READ) begin
            write_dma_rd_cmd(t);
        end else begin
            write_dma_wr_cmd(t);
        end
    endfunction : write

    // =========================================================================
    // Channel-Specific Analysis Implementation Callbacks
    // =========================================================================

    // 1. Read Descriptor Command Tap
    virtual function void write_dma_rd_cmd(item_type t);
        this.txn_rd_cmd = t;
        cg_dma_rd_desc.sample();
    endfunction : write_dma_rd_cmd

    // 2. Read Descriptor Status Tap
    virtual function void write_dma_rd_status(item_type t);
        this.txn_rd_status = t;
        cg_dma_rd_desc_status.sample();

        // Sample Cross-Tier Coverage on Read Completion
        cross_desc_align   = t.addr[1:0];
        cross_desc_len_cat = (t.len <= 64)   ? 0 :
                             (t.len <= 512)  ? 1 :
                             (t.len <= 4096) ? 2 : 3;
        cross_page_span    = ((t.addr[11:0] + t.len) > 4096) ? 1'b1 : 1'b0;
        cross_status_cat   = (t.status_error == DMA_ERR_NONE)          ? 0 :
                             (t.status_error == DMA_ERR_AXI_RD_SLVERR) ? 1 : 2;
        cross_direction    = 1'b0; // Read
        cg_cross_tier.sample();
    endfunction : write_dma_rd_status

    // 3. Write Descriptor Command Tap
    virtual function void write_dma_wr_cmd(item_type t);
        this.txn_wr_cmd = t;
        cg_dma_wr_desc.sample();
    endfunction : write_dma_wr_cmd

    // 4. Write Descriptor Status Tap
    virtual function void write_dma_wr_status(item_type t);
        this.txn_wr_status = t;
        cg_dma_wr_desc_status.sample();

        // Sample Write Abort Coverage
        is_write_aborted        = (t.status_len < t.len) || (t.status_error != DMA_ERR_NONE);
        abort_bytes_transferred = t.status_len;
        abort_status_error      = t.status_error;
        cg_write_abort.sample();

        // Sample Cross-Tier Coverage on Write Completion
        cross_desc_align   = t.addr[1:0];
        cross_desc_len_cat = (t.len <= 64)   ? 0 :
                             (t.len <= 512)  ? 1 :
                             (t.len <= 4096) ? 2 : 3;
        cross_page_span    = ((t.addr[11:0] + t.len) > 4096) ? 1'b1 : 1'b0;
        cross_status_cat   = (t.status_error == DMA_ERR_NONE)          ? 0 :
                             (t.status_error == DMA_ERR_AXI_WR_SLVERR) ? 1 : 2;
        cross_direction    = 1'b1; // Write
        cg_cross_tier.sample();
    endfunction : write_dma_wr_status

    // 5. Stream Read (Egress) Tap
    virtual function void write_axis_rd(axis_item_type t);
        this.axis_rd_txn = t;
        foreach (axis_rd_txn.keep[i]) begin
            current_rd_tkeep = axis_rd_txn.keep[i];
            is_rd_last_beat  = (i == axis_rd_txn.keep.size() - 1);
            cg_axis_rd_stream.sample();
        end
    endfunction : write_axis_rd

    // 6. Stream Write (Ingress) Tap
    virtual function void write_axis_wr(axis_item_type t);
        this.axis_wr_txn = t;
        foreach (axis_wr_txn.keep[i]) begin
            current_wr_tkeep = axis_wr_txn.keep[i];
            current_wr_delay = (i < axis_wr_txn.delay.size()) ? axis_wr_txn.delay[i] : 0;
            is_wr_last_beat  = (i == axis_wr_txn.keep.size() - 1);
            cg_axis_wr_stream.sample();
        end
    endfunction : write_axis_wr

    // 7. AXI-MM Read Master Tap
    virtual function void write_axi_rd(axi_item_type t);
        this.axi_rd_txn = t;
        cg_dma_axi_ar_master.sample();

        foreach (axi_rd_txn.rresp[i]) begin
            current_rresp = axi_rd_txn.rresp[i];
            is_rlast      = (i == axi_rd_txn.rresp.size() - 1);
            cg_dma_axi_r_master.sample();
        end
    endfunction : write_axi_rd

    // 8. AXI-MM Write Master Tap
    virtual function void write_axi_wr(axi_item_type t);
        this.axi_wr_txn = t;
        cg_dma_axi_aw_master.sample();

        total_wr_beats = t.strb.size();
        foreach (axi_wr_txn.strb[i]) begin
            current_wstrb = axi_wr_txn.strb[i];
            wr_beat_idx   = i;
            is_wlast      = (i == total_wr_beats - 1);
            cg_dma_axi_w_master.sample();
        end

        cg_dma_axi_b_master.sample();
    endfunction : write_axi_wr

endclass : dma_coverage

`endif // DMA_COVERAGE_SV
