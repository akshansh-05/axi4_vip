// File: dma_coverage.sv
// Description: Functional coverage model for the AXI4 DMA Subsystem.
//              Structured into 4 verification tiers:
//                - Tier 1: Descriptor Command & Status Channels (CG 1 - 4)
//                - Tier 2: AXI-Stream Egress & Ingress Datapaths (CG 5 - 6)
//                - Tier 3: AXI4-MM Master Channels (CG 7 - 11)
//                - Tier 4: Full-Duplex Concurrency & Fault Isolation (CG 12)

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
    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) desc_item_type;
    typedef axis_seq_item     #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) axis_item_type;
    typedef axi_seq_item      #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) axi_item_type;

    `uvm_component_param_utils(this_type)

    // Analysis Implementation Ports for all 8 passive monitor taps
    uvm_analysis_imp_dma_rd_cmd    #(desc_item_type, this_type) analysis_imp_dma_rd_cmd;
    uvm_analysis_imp_dma_rd_status #(desc_item_type, this_type) analysis_imp_dma_rd_status;
    uvm_analysis_imp_dma_wr_cmd    #(desc_item_type, this_type) analysis_imp_dma_wr_cmd;
    uvm_analysis_imp_dma_wr_status #(desc_item_type, this_type) analysis_imp_dma_wr_status;
    uvm_analysis_imp_axis_rd       #(axis_item_type, this_type) analysis_imp_axis_rd;
    uvm_analysis_imp_axis_wr       #(axis_item_type, this_type) analysis_imp_axis_wr;
    uvm_analysis_imp_axi_rd        #(axi_item_type,  this_type) analysis_imp_axi_rd;
    uvm_analysis_imp_axi_wr        #(axi_item_type,  this_type) analysis_imp_axi_wr;

    // Latched transaction handles for sampling
    desc_item_type       txn_rd_cmd;
    desc_item_type       txn_rd_status;
    desc_item_type       txn_wr_cmd;
    desc_item_type       txn_wr_status;
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

    // Concurrency state tracking (Feature 3 Full-Duplex)
    bit                  mm2s_in_flight;
    bit                  s2mm_in_flight;
    int                  concurrent_rd_len_cat;
    int                  concurrent_wr_len_cat;
    bit                  concurrent_rd_cross_4kb;
    bit                  concurrent_wr_cross_4kb;
    bit [1:0]            concurrent_error_status;

    // Covergroup 1: DMA Read Descriptor Channel (Command) [Tier 1]
    // Sampled when an MM2S read command handshake completes (valid && ready).
    // Exercises descriptor-level parameters: start address byte alignment, 4KB page
    // boundary proximity, and total transfer lengths across FSM operational domains.
    covergroup cg_dma_rd_desc;
        option.per_instance = 1;
        option.name = "cg_dma_rd_desc";

        // Memory start address byte alignment within a 32-bit word (addr[1:0]).
        // The DMA read master fetches 32-bit aligned words from memory; if the descriptor
        // specifies an unaligned start address, the DMA's internal byte-shifter must align
        // the read data before presenting it to the AXI-Stream interface.
        // We cover all 4 byte offsets to verify the internal shifter and initial TKEEP generation.
        cp_addr_align : coverpoint txn_rd_cmd.addr[1:0] {
            bins word_aligned    = {2'b00}; // Offset 0: clean word-aligned read (no shift needed)
            bins unaligned_byte1 = {2'b01}; // Offset 1: +1 byte shift required
            bins halfword_align  = {2'b10}; // Offset 2: +2 bytes shift (half-word aligned)
            bins unaligned_byte3 = {2'b11}; // Offset 3: +3 bytes shift
        }

        // Start offset within a 4KB memory page (addr[11:0]).
        // ARM AXI4 spec (Section A3.4.1) strictly forbids bursts from crossing a 4KB boundary.
        // The DMA address generator calculates remaining bytes to the page boundary
        // (12'hFFF - addr[11:0] + 1) and clamps the burst length accordingly.
        // We verify transfers starting right at page boundary, intra-page, and near page end.
        cp_page_offset : coverpoint txn_rd_cmd.addr[11:0] {
            bins page_start    = {12'h000};             // Exactly at page boundary
            bins mid_page      = {[12'h001 : 12'hFBF]}; // Normal intra-page transfer
            bins near_page_end = {[12'hFC0 : 12'hFFF]}; // Within 64B of 4KB edge; forces burst clamping
        }

        // Total byte count requested for this descriptor.
        // Grouped into 4 hardware execution domains:
        // - sub_word_len: < 1 word (1-3 bytes), single beat with TKEEP byte masking.
        // - single_burst_len: 4 to 64 bytes (1 to 16 beats of 4B). Fits in a single AXI burst;
        //   no FSM burst-looping required.
        // - multi_burst_len: 65 to 4096 bytes. Requires the read FSM to loop across multiple
        //   AXI bursts within a single page, updating address counters and byte remaining.
        // - multi_page_len: > 4096 bytes. Multi-page transfer crossing one or more 4KB boundaries,
        //   forcing the burst scheduler to repeatedly clamp and restart at each page edge.
        cp_transfer_len : coverpoint txn_rd_cmd.len {
            bins sub_word_len     = {[1 : 3]};        // < 1 word: single beat with TKEEP masking
            bins single_burst_len = {[4 : 64]};       // 1 to 16 beats: single AXI burst (no FSM loop)
            bins multi_burst_len  = {[65 : 4096]};     // Multiple AXI bursts within a page (FSM loops)
            bins multi_page_len   = {[4097 : 65535]}; // Multi-page transfer crossing 4KB boundaries
        }

        // Cross start address alignment with transfer length to verify that unaligned starts
        // function correctly across all transfer length regimes (especially sub-word transfers).
        cross_addr_align_x_len : cross cp_addr_align, cp_transfer_len;

        // Cross page offset with transfer length to ensure near-boundary starts are tested
        // across single-burst, multi-burst, and multi-page scenarios.
        cross_page_offset_x_len : cross cp_page_offset, cp_transfer_len;

    endgroup : cg_dma_rd_desc

    // Covergroup 2: DMA Read Descriptor Status Channel [Tier 1]
    // Sampled when the read engine completes a transfer and pulses read_desc_status_valid.
    // Verifies that the status bus accurately reports clean completions and errors to host.
    covergroup cg_dma_rd_desc_status;
        option.per_instance = 1;
        option.name = "cg_dma_rd_desc_status";

        // Read completion status code returned to host software.
        // - err_none (4'd0): Normal successful completion of the entire transfer.
        // - err_slverr (4'd4): Slave error returned on RRESP by memory slave.
        // - err_decerr (4'd5): Interconnect decode error returned on RRESP.
        // - illegal_bins: Write-specific error codes should never appear on the read status bus.
        cp_status_error : coverpoint txn_rd_status.status_error {
            bins err_none   = {DMA_ERR_NONE};          // 4'd0: Normal successful completion
            bins err_slverr = {DMA_ERR_AXI_RD_SLVERR}; // 4'd4: Slave error from memory
            bins err_decerr = {DMA_ERR_AXI_RD_DECERR}; // 4'd5: Decode error from interconnect
            illegal_bins err_wr_codes = {DMA_ERR_AXI_WR_SLVERR, DMA_ERR_AXI_WR_DECERR};
        }

    endgroup : cg_dma_rd_desc_status

    // Covergroup 3: DMA Write Descriptor Channel (Command) [Tier 1]
    // Sampled when an S2MM write command handshake completes (valid && ready).
    // Verifies destination address alignment, 4KB page offsets, and host buffer capacities.
    covergroup cg_dma_wr_desc;
        option.per_instance = 1;
        option.name = "cg_dma_wr_desc";

        // Destination start address byte alignment within a 32-bit word (addr[1:0]).
        // For unaligned writes, the DMA write master must assert only the valid byte strobes (WSTRB)
        // on the first beat of the AXI write burst so unrequested memory bytes are not overwritten.
        cp_wr_addr_align : coverpoint txn_wr_cmd.addr[1:0] {
            bins word_aligned    = {2'b00}; // Starts at Byte 0 (first beat WSTRB = 4'b1111)
            bins unaligned_byte1 = {2'b01}; // Starts at Byte 1 (first beat WSTRB = 4'b1110)
            bins halfword_align  = {2'b10}; // Starts at Byte 2 (first beat WSTRB = 4'b1100)
            bins unaligned_byte3 = {2'b11}; // Starts at Byte 3 (first beat WSTRB = 4'b1000)
        }

        // Destination start offset within a 4KB memory page (addr[11:0]).
        // Tests the write address generator's ability to detect 4KB page proximity and clamp AWLEN.
        cp_wr_page_offset : coverpoint txn_wr_cmd.addr[11:0] {
            bins page_start    = {12'h000};             // Exactly at page boundary
            bins mid_page      = {[12'h001 : 12'hFBF]}; // Normal intra-page transfer
            bins near_page_end = {[12'hFC0 : 12'hFFF]}; // Within 64B of 4KB edge; forces burst clamp
        }

        // Host-allocated buffer capacity in bytes.
        // Grouped into the same 4 hardware operational domains as the read channel:
        // sub-word (<4B), single burst (4-64B), multi-burst (65-4096B), and multi-page (>4KB).
        cp_wr_buffer_len : coverpoint txn_wr_cmd.len {
            bins sub_word_len     = {[1 : 3]};        // < 1 word: single beat with WSTRB masking
            bins single_burst_len = {[4 : 64]};       // 1 to 16 beats: single AXI burst
            bins multi_burst_len  = {[65 : 4096]};     // Multiple AXI bursts within a page
            bins multi_page_len   = {[4097 : 65535]}; // Multi-page transfer crossing 4KB boundaries
        }

        // Cross destination address alignment with buffer capacity
        cross_wr_align_x_len : cross cp_wr_addr_align, cp_wr_buffer_len;

        // Cross page offset with buffer capacity to ensure boundary clamping is verified across sizes
        cross_wr_page_x_len  : cross cp_wr_page_offset, cp_wr_buffer_len;

    endgroup : cg_dma_wr_desc

    // Covergroup 4: DMA Write Descriptor Status Channel [Tier 1]
    // Sampled when the write engine completes a transfer and pulses write_desc_status_valid.
    // Verifies status error codes and actual transferred byte count vs host buffer capacity.
    covergroup cg_dma_wr_desc_status;
        option.per_instance = 1;
        option.name         = "cg_dma_wr_desc_status";

        // Write completion error status code returned to host.
        // Verifies clean write completion as well as slave/decode errors reported via BRESP.
        // Read error codes are flagged illegal to catch internal status decoding bugs.
        cp_wr_status_error : coverpoint txn_wr_status.status_error {
            bins err_none   = {DMA_ERR_NONE};          // 4'd0: Normal successful write
            bins err_slverr = {DMA_ERR_AXI_WR_SLVERR}; // 4'd6: Slave error from memory (BRESP)
            bins err_decerr = {DMA_ERR_AXI_WR_DECERR}; // 4'd7: Decode error from interconnect (BRESP)
            illegal_bins err_rd_codes = {DMA_ERR_AXI_RD_SLVERR, DMA_ERR_AXI_RD_DECERR};
        }

        // Compares written bytes (status_len) against requested buffer size (len).
        // - full_buffer_transfer: Stream provided enough data to fill the buffer (status_len == len).
        // - early_stream_tlast: Stream asserted TLAST before buffer filled (Scenario 2.7).
        //   The DMA terminates the descriptor early and reports actual received byte count.
        // - zero_byte_abort: Immediate TLAST or error abort before any bytes written (status_len == 0).
        cp_wr_status_len : coverpoint (
            (txn_wr_status.status_len == txn_wr_status.len) ? 2 :
            ((txn_wr_status.status_len < txn_wr_status.len) && (txn_wr_status.status_len > 0)) ? 1 : 0
        ) {
            bins full_buffer_transfer = {2}; // status_len == len (stream filled the buffer)
            bins early_stream_tlast   = {1}; // status_len < len  (stream ended early via TLAST)
            bins zero_byte_abort      = {0}; // status_len == 0   (zero-length transfer)
        }

    endgroup : cg_dma_wr_desc_status

    // Covergroup 5: AXI4-Stream Read Data Channel (Egress Stream from DUT) [Tier 2]
    // Sampled on accepted stream beats (m_axis_read_data_tvalid && tready).
    // Verifies packet beat counts, trailing byte masks, and downstream consumer backpressure.
    covergroup cg_axis_rd_stream;
        option.per_instance = 1;
        option.name = "cg_axis_rd_stream";

        // Trailing byte enable qualifiers on the final packet beat (TKEEP).
        // Per ARM AXI-Stream spec, valid bytes within a continuous packet must be contiguous.
        // On the final beat (TLAST), TKEEP indicates trailing unaligned bytes:
        // 4'b1111 (full 4 bytes), 4'b0111 (3 bytes), 4'b0011 (2 bytes), 4'b0001 (1 byte).
        // 4'b0000 is illegal because TLAST must accompany at least one valid byte.
        cp_rd_last_tkeep : coverpoint current_rd_tkeep iff (is_rd_last_beat) {
            bins full_word    = {4'b1111}; // 4 active bytes (aligned word end)
            bins three_bytes  = {4'b0111}; // 3 active bytes (unaligned length)
            bins two_bytes    = {4'b0011}; // 2 active bytes (half-word end)
            bins single_byte  = {4'b0001}; // 1 active byte (odd byte length)
            illegal_bins zero = {4'b0000}; // Illegal in AXI-Stream for valid beat
        }

        // Egress packet size measured in stream beats.
        // Covers single-beat packets (sub-word/single-word), single-burst packets (2-16 beats),
        // and multi-burst assembled packets (17-256 beats).
        cp_rd_packet_beats : coverpoint axis_rd_txn.data.size() {
            bins single_beat       = {1};            // 1-beat packet (TLAST on beat 0)
            bins single_burst_pkt  = {[2 : 16]};     // Single AXI burst (<=64B)
            bins multi_burst_pkt   = {[17 : 256]};   // Multi-burst assembled packet
        }

        // Downstream receiver throttling: cycles TREADY is withheld by the consumer VIP.
        // Stresses the internal MM2S read FIFO watermark and backpressure logic,
        // verifying that the DMA stalls read requests when the downstream sink is slow.
        cp_rd_backpressure : coverpoint axis_rd_txn.ready_delay {
            bins zero_delay   = {0};             // Full wire-speed (TREADY continuously high)
            bins short_stall  = {[1 : 3]};       // Short 1-3 cycle pauses
            bins med_stall    = {[4 : 10]};      // Moderate consumer throttle
            bins heavy_stall  = {[11 : 30]};     // Heavy backpressure; fills FIFO
        }

        // Verify trailing byte masks across all packet length categories
        cross_rd_pkt_len_x_last_tkeep : cross cp_rd_packet_beats, cp_rd_last_tkeep;

    endgroup : cg_axis_rd_stream

    // Covergroup 6: AXI4-Stream Write Data Channel (Ingress Stream to DUT) [Tier 2]
    // Sampled on accepted ingress stream beats (s_axis_write_data_tvalid && tready).
    // Verifies incoming packet lengths, trailing byte qualifiers, and producer bubbles.
    covergroup cg_axis_wr_stream;
        option.per_instance = 1;
        option.name = "cg_axis_wr_stream";

        // Ingress packet byte enable on the final beat (TKEEP).
        // Verifies that the S2MM stream receiver correctly accepts packets ending on any
        // byte boundary (1, 2, 3, or 4 valid bytes).
        cp_wr_last_tkeep : coverpoint current_wr_tkeep iff (is_wr_last_beat) {
            bins full_word    = {4'b1111}; // 4 active bytes
            bins three_bytes  = {4'b0111}; // 3 active bytes
            bins two_bytes    = {4'b0011}; // 2 active bytes
            bins single_byte  = {4'b0001}; // 1 active byte
            illegal_bins zero = {4'b0000}; // Illegal in AXI-Stream for valid beat
        }

        // Ingress packet length in stream beats
        cp_wr_packet_beats : coverpoint axis_wr_txn.data.size() {
            bins single_beat       = {1};            // 1-beat packet (TLAST on beat 0)
            bins single_burst_pkt  = {[2 : 16]};     // Single AXI burst (<=64B)
            bins multi_burst_pkt   = {[17 : 256]};   // Multi-burst assembled packet
        }

        // Upstream transmitter bubbles: idle cycles between valid ingress beats (TVALID stalls).
        // Tests the S2MM input datapath's ability to hold partial words across stalls
        // without dropping data or prematurely triggering an AXI write burst.
        cp_wr_inter_beat_delay : coverpoint current_wr_delay {
            bins back_to_back = {0};             // Consecutive beats (0 cycle bubble)
            bins short_pause  = {[1 : 3]};       // 1-3 cycle pause between beats
            bins med_pause    = {[4 : 10]};      // Moderate producer pacing
            bins long_pause   = {[11 : 30]};     // Sparse stream transmission
        }

        // Verify trailing byte masks across all ingress packet lengths
        cross_wr_pkt_len_x_last_tkeep : cross cp_wr_packet_beats, cp_wr_last_tkeep;

    endgroup : cg_axis_wr_stream

    // Covergroup 7: DMA AXI-MM Read Address Channel (AR Master) [Tier 3]
    // Sampled on AXI Read Address handshake (m_axi_arvalid && arready).
    // Verifies ARLEN burst lengths, ARADDR alignment, 4KB page offsets, and protocol compliance.
    covergroup cg_dma_axi_ar_master;
        option.per_instance = 1;
        option.name         = "cg_dma_axi_ar_master";

        // AXI Read Burst Length (ARLEN = beats - 1, 0 to 15).
        // Covers single-beat transfers (ARLEN=0), short/clamped bursts (1 to 14 beats),
        // and the maximum 16-beat burst (ARLEN=15).
        // ARLEN > 15 is flagged illegal because the DMA RTL has a 16-beat maximum burst limit.
        cp_ar_len : coverpoint axi_rd_txn.len {
            bins single_beat               = {0};          // 1 beat transfer (ARLEN=0, immediate RLAST)
            bins short_burst               = {[1 : 14]};   // 2 to 15 beats (partial / clamped)
            bins max_burst                 = {15};         // 16 beats (AXI_MAX_BURST_LEN limit)
            illegal_bins exceeds_dma_burst = {[16 : 255]}; // RTL arithmetic overflow check
        }

        // Beat transfer size (ARSIZE).
        // Hardwired in RTL to 3'b010 (4 bytes = 32-bit data bus).
        // Narrow or oversize transfers are flagged illegal to confirm protocol compliance.
        cp_ar_size : coverpoint axi_rd_txn.size {
            bins size_4B                    = {3'b010};                 // Full 32-bit width (4 bytes per beat)
            illegal_bins narrow_or_oversize = {3'b000, 3'b001, [3'b011 : 3'b111]};
        }

        // Burst type (ARBURST).
        // Hardwired in RTL to 2'b01 (INCR). FIXED and WRAP bursts are illegal for this DMA.
        cp_ar_burst : coverpoint axi_rd_txn.burst {
            bins burst_incr       = {AXI_BURST_INCR};      // Sequential INCR burst
            illegal_bins non_incr = {AXI_BURST_FIXED, AXI_BURST_WRAP, AXI_BURST_RSVD};
        }

        // Physical bus address alignment bits [1:0]
        cp_ar_addr_align : coverpoint axi_rd_txn.addr[1:0] {
            bins word_aligned    = {2'b00};          // 4-byte word aligned
            bins unaligned_byte1 = {2'b01};          // +1 byte offset
            bins halfword_align  = {2'b10};          // +2 bytes offset
            bins unaligned_byte3 = {2'b11};          // +3 bytes offset
        }

        // 4KB memory page offset (ARADDR[11:0]).
        // Verifies address generation at page start, mid-page, and near the 4KB boundary.
        cp_ar_page_offset : coverpoint axi_rd_txn.addr[11:0] {
            bins page_start    = {12'h000};             // Exactly at page boundary
            bins mid_page      = {[12'h001 : 12'hFBF]}; // Normal intra-page transfer
            bins near_page_end = {[12'hFC0 : 12'hFFF]}; // Within 64 bytes of 4KB edge (triggers burst clamping)
        }

        // Cross address alignment with burst lengths
        cross_ar_align_x_len : cross cp_ar_addr_align, cp_ar_len;

        // Cross page offset with burst lengths.
        // Near page end with max burst (16 beats = 64B) is physically impossible because
        // the DMA address generator clamps ARLEN to avoid crossing the 4KB boundary,
        // so it is appropriately marked with ignore_bins.
        cross_ar_offset_x_len : cross cp_ar_page_offset, cp_ar_len {
            ignore_bins impossible_max_burst_at_page_end = 
                binsof(cp_ar_page_offset.near_page_end) && binsof(cp_ar_len.max_burst);
        }

    endgroup : cg_dma_axi_ar_master

    // Covergroup 8: DMA AXI-MM Read Data Channel (R Master) [Tier 3]
    // Sampled on each accepted read data beat (m_axi_rvalid && rready).
    // Verifies RRESP response codes, burst completion (RLAST), and error handling.
    covergroup cg_dma_axi_r_master;
        option.per_instance = 1;
        option.name         = "cg_dma_axi_r_master";

        // Read data response code from slave memory (RRESP).
        // Verifies normal success (OKAY = 2'b00), slave error (SLVERR = 2'b10), and decode error (DECERR = 2'b11).
        // EXOKAY (2'b01) is ignored because the DMA master does not support atomic exclusive accesses (AxLOCK).
        cp_rresp : coverpoint current_rresp {
            bins resp_okay   = {2'b00};              // Normal success (OKAY)
            bins resp_slverr = {2'b10};              // Slave error
            bins resp_decerr = {2'b11};              // Decode error
            ignore_bins resp_exokay = {2'b01};       // Not applicable to DMA master (no AxLOCK)
        }

        // Beat position within burst (RLAST)
        cp_rlast : coverpoint is_rlast {
            bins intermediate_beat = {0};
            bins last_burst_beat   = {1};
        }

        // Cross RRESP with RLAST.
        // Proves that error responses (SLVERR and DECERR) are verified when received
        // on intermediate burst beats as well as on the final burst beat.
        cross_rresp_x_rlast : cross cp_rresp, cp_rlast;

    endgroup : cg_dma_axi_r_master

    // Covergroup 9: DMA AXI-MM Write Address Channel (AW Master) [Tier 3]
    // Sampled on AXI Write Address handshake (m_axi_awvalid && awready).
    // Verifies AWLEN burst lengths, AWADDR alignment, 4KB page offsets, and protocol compliance.
    covergroup cg_dma_axi_aw_master;
        option.per_instance = 1;
        option.name         = "cg_dma_axi_aw_master";

        // AXI Write Burst Length (AWLEN: 0 to 15, beats = len + 1).
        // Covers single-beat transfers (AWLEN=0), short/clamped bursts (1 to 14 beats),
        // and the maximum 16-beat burst (AWLEN=15).
        // AWLEN > 15 is flagged illegal because the DMA RTL has a 16-beat maximum burst limit.
        cp_aw_len : coverpoint axi_wr_txn.len {
            bins single_beat               = {0};          // 1 beat transfer (AWLEN=0)
            bins short_burst               = {[1 : 14]};   // 2 to 15 beats (partial / clamped)
            bins max_burst                 = {15};         // 16 beats (AXI_MAX_BURST_LEN limit)
            illegal_bins exceeds_dma_burst = {[16 : 255]}; // DMA must never exceed max burst len
        }

        // AXI Write Transfer Size (AWSIZE).
        // Hardwired in RTL to 3'b010 (4 bytes = 32-bit data bus).
        // Other sizes flagged illegal to confirm protocol compliance.
        cp_aw_size : coverpoint axi_wr_txn.size {
            bins size_4B                    = {3'b010};                 // Full 32-bit width (4 bytes per beat)
            illegal_bins narrow_or_oversize = {3'b000, 3'b001, [3'b011 : 3'b111]};
        }

        // AXI Write Burst Type (AWBURST).
        // Hardwired in RTL to 2'b01 (INCR). FIXED and WRAP bursts are illegal for this DMA.
        cp_aw_burst : coverpoint axi_wr_txn.burst {
            bins burst_incr       = {AXI_BURST_INCR};      // Sequential INCR burst
            illegal_bins non_incr = {AXI_BURST_FIXED, AXI_BURST_WRAP, AXI_BURST_RSVD};
        }

        // AXI Write Address Alignment (AWADDR[1:0])
        cp_aw_addr_align : coverpoint axi_wr_txn.addr[1:0] {
            bins word_aligned    = {2'b00};          // 4-byte word aligned
            bins unaligned_byte1 = {2'b01};          // +1 byte offset
            bins halfword_align  = {2'b10};          // +2 bytes offset
            bins unaligned_byte3 = {2'b11};          // +3 bytes offset
        }

        // 4KB Page Offset (AWADDR[11:0]).
        // Verifies address generation at page start, mid-page, and near the 4KB boundary.
        cp_aw_page_offset : coverpoint axi_wr_txn.addr[11:0] {
            bins page_start    = {12'h000};             // Exactly at page boundary
            bins mid_page      = {[12'h001 : 12'hFBF]}; // Normal intra-page transfer
            bins near_page_end = {[12'hFC0 : 12'hFFF]}; // Within 64 bytes of 4KB edge (triggers burst clamping)
        }

        // Cross address alignment with burst length (4 x 3 = 12 bins)
        cross_aw_align_x_len : cross cp_aw_addr_align, cp_aw_len;

        // Cross 4KB page offset with burst length.
        // Near page end with max burst (16 beats) is physically impossible because
        // hardware clamps tr_word_count at the 4KB boundary, so it is ignored.
        cross_aw_offset_x_len : cross cp_aw_page_offset, cp_aw_len {
            ignore_bins impossible_max_burst_at_page_end = 
                binsof(cp_aw_page_offset.near_page_end) && binsof(cp_aw_len.max_burst);
        }

    endgroup : cg_dma_axi_aw_master

    // Covergroup 10: DMA AXI-MM Write Data Channel (W Master) [Tier 3]
    // Sampled on each accepted write data beat (m_axi_wvalid && wready).
    // Verifies WSTRB byte-lane enables across burst phases: first beat start alignment,
    // intermediate beats (full words vs early TLAST zero-padding), last beat trailing bytes,
    // and isolated single-beat sub-word transfers.
    covergroup cg_dma_axi_w_master;
        option.per_instance = 1;
        option.name = "cg_dma_axi_w_master";

        // First Beat WSTRB for Multi-Beat Bursts (total_wr_beats > 1).
        // Isolates start address alignment:
        // - 4'b1111: Word-aligned start (offset 0, all 4 bytes valid)
        // - 4'b1110: Starts at byte 1 (offset 1, lower byte masked)
        // - 4'b1100: Starts at byte 2 (offset 2, lower 2 bytes masked)
        // - 4'b1000: Starts at byte 3 (offset 3, lower 3 bytes masked)
        cp_wstrb_first_beat : coverpoint current_wstrb iff (wr_beat_idx == 0 && total_wr_beats > 1) {
            bins strb_aligned = {4'b1111};           // Starts at byte 0 (aligned)
            bins strb_byte1   = {4'b1110};           // Starts at byte 1 (unaligned)
            bins strb_byte2   = {4'b1100};           // Starts at byte 2 (half-word)
            bins strb_byte3   = {4'b1000};           // Starts at byte 3 (unaligned)
        }

        // Intermediate Beat WSTRB for Multi-Beat Bursts (0 < wr_beat_idx < total_wr_beats - 1).
        // In normal operation, middle beats always write full 32-bit words (4'b1111).
        // When an early TLAST arrives on the ingress stream (Scenario 2.7), the AXI spec
        // strictly forbids truncating an active AWLEN burst. The DMA RTL enters STATE_FINISH_BURST
        // and sends dummy padding beats with WSTRB = 4'b0000 so memory is not corrupted.
        cp_wstrb_mid_beats : coverpoint current_wstrb iff (wr_beat_idx > 0 && wr_beat_idx < total_wr_beats - 1) {
            bins strb_full      = {4'b1111};          // All bytes active in middle beats
            bins dummy_zero_pad = {4'b0000};          // Early TLAST padding beats (Scenario 2.7)
        }

        // Last Beat WSTRB for Multi-Beat Bursts (wr_beat_idx == total_wr_beats - 1 && total_wr_beats > 1).
        // Verifies all valid trailing byte boundaries:
        // - 4'b1111: Full word end (ends on byte 3)
        // - 4'b0111: Ends on byte 2
        // - 4'b0011: Ends on byte 1 (half-word end)
        // - 4'b0001: Ends on byte 0
        // - 4'b0000: Early TLAST padding continues through the final burst beat
        cp_wstrb_last_beat : coverpoint current_wstrb iff (wr_beat_idx == total_wr_beats - 1 && total_wr_beats > 1) {
            bins full_word      = {4'b1111};          // Full word end (byte 3)
            bins three_bytes    = {4'b0111};          // Ends at byte 2
            bins two_bytes      = {4'b0011};          // Ends at byte 1
            bins single_byte    = {4'b0001};          // Ends at byte 0
            bins dummy_zero_pad = {4'b0000};          // Early TLAST padding ends on last beat
        }

        // Single-Beat Transfer WSTRB (total_wr_beats == 1).
        // Sub-word transfers (< 4 bytes) that start and end within the same word can produce
        // middle-slice byte masks (e.g., 4'b0010, 4'b0110, 4'b0100, 4'b1100).
        // Isolating single-beat transfers prevents these legal sub-word masks from causing
        // false coverage holes or illegal bin violations in multi-beat coverpoints.
        cp_wstrb_single_beat : coverpoint current_wstrb iff (total_wr_beats == 1) {
            bins full_word         = {4'b1111};       // 4 bytes aligned (addr[1:0]=0, len=4)
            bins aligned_trailing  = {4'b0001, 4'b0011, 4'b0111}; // Aligned start with partial len
            bins unaligned_subword = {4'b0010, 4'b0100, 4'b1000,  // 1-byte unaligned slices
                                      4'b0110, 4'b1100,           // 2-byte unaligned slices
                                      4'b1110};                   // 3-byte unaligned slice
            bins dummy_zero_pad    = {4'b0000};       // Immediate zero-byte early TLAST
        }

        // Write Last Beat Indicator (WLAST)
        cp_wlast : coverpoint is_wlast {
            bins intermediate_beat = {0};
            bins last_burst_beat   = {1};
        }

    endgroup : cg_dma_axi_w_master

    // Covergroup 11: DMA AXI-MM Write Response Channel (B Master) [Tier 3]
    // Sampled on Write Response handshake (m_axi_bvalid && bready).
    // Verifies write response status codes (BRESP) returned by slave memory.
    covergroup cg_dma_axi_b_master;
        option.per_instance = 1;
        option.name = "cg_dma_axi_b_master";

        // Write Response Status Code (BRESP).
        // Verifies successful writes (OKAY = 2'b00), slave error (SLVERR = 2'b10),
        // and interconnect decode error (DECERR = 2'b11).
        // EXOKAY (2'b01) is ignored because the DMA master does not issue exclusive writes.
        cp_bresp : coverpoint axi_wr_txn.bresp {
            bins resp_okay   = {2'b00};              // Normal success (OKAY)
            bins resp_slverr = {2'b10};              // Slave error
            bins resp_decerr = {2'b11};              // Decode error
            ignore_bins resp_exokay = {2'b01};       // Not applicable to DMA master (no AxLOCK)
        }

    endgroup : cg_dma_axi_b_master

    // Covergroup 12: DMA Full-Duplex Concurrency & Engine Isolation [Tier 4]
    // Sampled on descriptor launch and completion events.
    // Verifies Feature 3: Concurrent dual-engine execution, asymmetric load, and fault isolation.
    covergroup cg_dma_concurrency;
        option.per_instance = 1;
        option.name = "cg_dma_concurrency";

        // Subsystem Operating Mode (Scenario 3.1)
        cp_concurrency_mode : coverpoint {s2mm_in_flight, mm2s_in_flight} {
            bins simplex_rd_only = {2'b01}; // MM2S active, S2MM idle
            bins simplex_wr_only = {2'b10}; // S2MM active, MM2S idle
            bins full_duplex     = {2'b11}; // Both engines actively executing concurrently!
        }

        // Concurrent Transfer Length Scale (Scenario 3.3 Asymmetric Load)
        cp_rd_len_scale : coverpoint concurrent_rd_len_cat iff (s2mm_in_flight && mm2s_in_flight) {
            bins short_burst = {0}; // 1 to 64B
            bins multi_burst = {1}; // 65 to 4096B
            bins multi_page  = {2}; // > 4096B
        }

        cp_wr_len_scale : coverpoint concurrent_wr_len_cat iff (s2mm_in_flight && mm2s_in_flight) {
            bins short_burst = {0}; // 1 to 64B
            bins multi_burst = {1}; // 65 to 4096B
            bins multi_page  = {2}; // > 4096B
        }

        // Asymmetric Length Concurrency (Scenario 3.3)
        cross_concurrent_length_ratio : cross cp_rd_len_scale, cp_wr_len_scale;

        // Simultaneous 4KB Page Crossing (Scenario 3.5)
        cp_rd_cross_4kb : coverpoint concurrent_rd_cross_4kb iff (s2mm_in_flight && mm2s_in_flight) {
            bins intra_page = {0};
            bins crosses_4k = {1};
        }
        cp_wr_cross_4kb : coverpoint concurrent_wr_cross_4kb iff (s2mm_in_flight && mm2s_in_flight) {
            bins intra_page = {0};
            bins crosses_4k = {1};
        }

        // Dual 4KB Boundary Stress (Scenario 3.5)
        cross_dual_4kb_crossing : cross cp_rd_cross_4kb, cp_wr_cross_4kb;

        // Concurrent Fault Isolation (Scenario 3.4)
        cp_concurrent_fault_isolation : coverpoint concurrent_error_status iff (s2mm_in_flight && mm2s_in_flight) {
            bins both_clean      = {2'b00}; // Both completed OKAY
            bins rd_err_wr_clean = {2'b01}; // MM2S hit SLVERR/DECERR, S2MM completed OKAY
            bins wr_err_rd_clean = {2'b10}; // S2MM hit SLVERR/DECERR, MM2S completed OKAY
        }

    endgroup : cg_dma_concurrency

    // Component Constructor: instantiate all 12 functional covergroups
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
        cg_dma_concurrency    = new();
    endfunction : new

    // UVM Build Phase: initialize analysis implementation subscriber ports
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

    // Default UVM Subscriber write method (routes descriptor transactions by type)
    virtual function void write(desc_item_type t);
        if (t.trans_type == DESC_READ) begin
            write_dma_rd_cmd(t);
        end else begin
            write_dma_wr_cmd(t);
        end
    endfunction : write

    // Analysis implementation callback methods (passive monitor taps)

    // 1. Read Descriptor Command Tap
    virtual function void write_dma_rd_cmd(desc_item_type t);
        this.txn_rd_cmd = t;
        mm2s_in_flight  = 1'b1;
        concurrent_rd_len_cat   = (t.len <= 64) ? 0 : (t.len <= 4096) ? 1 : 2;
        concurrent_rd_cross_4kb = ((t.addr[11:0] + t.len) > 4096);
        cg_dma_rd_desc.sample();
        cg_dma_concurrency.sample();
    endfunction : write_dma_rd_cmd

    // 2. Read Descriptor Status Tap
    virtual function void write_dma_rd_status(desc_item_type t);
        this.txn_rd_status = t;
        cg_dma_rd_desc_status.sample();

        if (s2mm_in_flight) begin
            bit rd_err = (t.status_error != DMA_ERR_NONE);
            bit wr_err = (txn_wr_status != null && txn_wr_status.status_error != DMA_ERR_NONE);
            concurrent_error_status = {wr_err, rd_err};
            cg_dma_concurrency.sample();
        end
        mm2s_in_flight = 1'b0;
    endfunction : write_dma_rd_status

    // 3. Write Descriptor Command Tap
    virtual function void write_dma_wr_cmd(desc_item_type t);
        this.txn_wr_cmd = t;
        s2mm_in_flight  = 1'b1;
        concurrent_wr_len_cat   = (t.len <= 64) ? 0 : (t.len <= 4096) ? 1 : 2;
        concurrent_wr_cross_4kb = ((t.addr[11:0] + t.len) > 4096);
        cg_dma_wr_desc.sample();
        cg_dma_concurrency.sample();
    endfunction : write_dma_wr_cmd

    // 4. Write Descriptor Status Tap
    virtual function void write_dma_wr_status(desc_item_type t);
        this.txn_wr_status = t;
        cg_dma_wr_desc_status.sample();

        if (mm2s_in_flight) begin
            bit wr_err = (t.status_error != DMA_ERR_NONE);
            bit rd_err = (txn_rd_status != null && txn_rd_status.status_error != DMA_ERR_NONE);
            concurrent_error_status = {wr_err, rd_err};
            cg_dma_concurrency.sample();
        end
        s2mm_in_flight = 1'b0;
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
