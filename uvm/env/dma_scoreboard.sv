// File: dma_scoreboard.sv
// Description: End-to-End Functional Scoreboard for AXI4 DMA Subsystem Verification.
//              Contains two independent, fully decoupled checking engines:
//              1. MM2S Engine (Memory -> Stream):
//                 - Slices AXI-MM read bursts into expected stream bytes.
//                 - Validates AXI read burst addresses and progression.
//                 - Matches egress stream payload byte-for-byte, verifying 1-to-1 packet
//                   boundary framing, TLAST positioning, and final TKEEP.
//                 - Validates MM2S completion status tag and error code.
//              2. S2MM Engine (Stream -> Memory):
//                 - Ingests incoming stream payload bytes as golden reference.
//                 - Validates 1-to-1 stream packet boundary framing per descriptor.
//                 - Matches AXI-MM write burst payload against absolute destination byte addresses.
//                 - Verifies WSTRB lane placement and unaligned start/end strobe masking.
//                 - Validates S2MM completion status_len, tag, and error code.
//              3. Decoupled Concurrency & Burst Resilience:
//                 - Incremental pair-wise drain prevents false mismatches regardless of
//                   whether AXI bursts or AXIS packets complete first.
//                 - Tag-indexed maps support concurrent full-duplex operation with zero blocking.
//                 - Enforces in-order completion within each engine while cleanly deleting completed
//                   descriptors by tag.
//              4. Authoritative Cleanliness & Verdict:
//                 - check_phase flags orphan/hung descriptors or uncompared bytes.
//                 - report_phase includes outstanding queues, packet errors, and address errors
//                   directly in the authoritative Pass/Fail verification scorecard verdict.

`ifndef DMA_SCOREBOARD_SV
`define DMA_SCOREBOARD_SV

`ifndef DMA_IMP_DECLS
`define DMA_IMP_DECLS
`uvm_analysis_imp_decl(_dma_rd_cmd)
`uvm_analysis_imp_decl(_dma_rd_status)
`uvm_analysis_imp_decl(_dma_wr_cmd)
`uvm_analysis_imp_decl(_dma_wr_status)
`uvm_analysis_imp_decl(_axis_rd)
`uvm_analysis_imp_decl(_axis_wr)
`uvm_analysis_imp_decl(_axi_rd)
`uvm_analysis_imp_decl(_axi_wr)
`endif

// =============================================================================
// Helper Descriptor Tracking Classes
// =============================================================================

class mm2s_desc_txn #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8
);
    bit [ADDR_WIDTH-1:0] start_addr;
    bit [LEN_WIDTH-1:0]  xfer_len;
    bit [TAG_WIDTH-1:0]  tag;
    byte                 expected_bytes[$]; // Golden bytes sliced from AXI-MM read bursts
    byte                 actual_bytes[$];   // Egress stream bytes observed on AXIS
    int unsigned         total_bytes_expected;
    int unsigned         bytes_matched;
    int unsigned         packet_count;      // Number of stream packets observed (must be exactly 1)
    int unsigned         stream_pkt_bytes;  // Total bytes in the observed stream packet
    bit [ADDR_WIDTH-1:0] expected_next_burst_addr; // Next expected AXI read burst address
    bit                  cmd_seen;
    bit                  stream_done;
    bit                  status_done;

    function new();
        expected_bytes            = {};
        actual_bytes              = {};
        total_bytes_expected      = 0;
        bytes_matched             = 0;
        packet_count              = 0;
        stream_pkt_bytes          = 0;
        expected_next_burst_addr  = '0;
        cmd_seen                  = 1'b0;
        stream_done               = 1'b0;
        status_done               = 1'b0;
    endfunction
endclass : mm2s_desc_txn

class s2mm_desc_txn #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8
);
    bit [ADDR_WIDTH-1:0] dest_addr;
    bit [LEN_WIDTH-1:0]  buffer_len;
    bit [TAG_WIDTH-1:0]  tag;
    byte                 stream_in_bytes[$]; // Golden ingress stream payload bytes
    byte                 axi_wr_bytes[$];    // Actual bytes written by DMA master to AXI-MM
    int unsigned         total_stream_bytes;
    int unsigned         bytes_matched;
    int unsigned         packet_count;       // Number of stream packets observed (must be exactly 1)
    int unsigned         stream_pkt_bytes;   // Total bytes in the observed stream packet
    bit [ADDR_WIDTH-1:0] expected_next_byte_addr;  // Next expected memory byte address for WSTRB
    bit [ADDR_WIDTH-1:0] expected_next_burst_addr; // Next expected AXI write burst address
    bit                  first_burst_seen;
    bit                  cmd_seen;
    bit                  stream_done;
    bit                  status_done;

    function new();
        stream_in_bytes           = {};
        axi_wr_bytes              = {};
        total_stream_bytes        = 0;
        bytes_matched             = 0;
        packet_count              = 0;
        stream_pkt_bytes          = 0;
        expected_next_byte_addr   = '0;
        expected_next_burst_addr  = '0;
        first_burst_seen          = 1'b0;
        cmd_seen                  = 1'b0;
        stream_done               = 1'b0;
        status_done               = 1'b0;
    endfunction
endclass : s2mm_desc_txn

// =============================================================================
// Top DMA Scoreboard Component
// =============================================================================

class dma_scoreboard #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_scoreboard;

    `uvm_component_param_utils(dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH))

    typedef axi_seq_item      #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH)                        axi_item_type;
    typedef axis_seq_item     #(DATA_WIDTH, STRB_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH)            axis_item_type;
    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) dma_desc_item_type;

    typedef mm2s_desc_txn #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH) mm2s_txn_type;
    typedef s2mm_desc_txn #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH) s2mm_txn_type;

    // -------------------------------------------------------------------------
    // 1. Analysis Exports (8 Passive Monitor Interfaces)
    // -------------------------------------------------------------------------
    uvm_analysis_imp_dma_rd_cmd    #(dma_desc_item_type, dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_dma_rd_cmd;
    uvm_analysis_imp_dma_rd_status #(dma_desc_item_type, dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_dma_rd_status;
    uvm_analysis_imp_dma_wr_cmd    #(dma_desc_item_type, dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_dma_wr_cmd;
    uvm_analysis_imp_dma_wr_status #(dma_desc_item_type, dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_dma_wr_status;
    uvm_analysis_imp_axis_rd       #(axis_item_type,     dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_axis_rd;
    uvm_analysis_imp_axis_wr       #(axis_item_type,     dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_axis_wr;
    uvm_analysis_imp_axi_rd        #(axi_item_type,      dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_axi_rd;
    uvm_analysis_imp_axi_wr        #(axi_item_type,      dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_axi_wr;

    // -------------------------------------------------------------------------
    // 2. Internal Transfer Records & Tracking Queues
    // -------------------------------------------------------------------------
    // Architectural Note: The AXI DMA hardware pipelines MM2S and S2MM as two
    // independent single-descriptor FSMs. Within each engine, descriptors execute
    // strictly in FIFO order. Across engines, execution is fully concurrent and decoupled.
    mm2s_txn_type mm2s_queue[$];
    s2mm_txn_type s2mm_queue[$];

    mm2s_txn_type mm2s_by_tag[bit [TAG_WIDTH-1:0]];
    s2mm_txn_type s2mm_by_tag[bit [TAG_WIDTH-1:0]];

    // -------------------------------------------------------------------------
    // 3. Statistical Verification Counters
    // -------------------------------------------------------------------------
    int unsigned mm2s_cmd_count;
    int unsigned mm2s_status_count;
    int unsigned mm2s_bytes_checked;
    int unsigned mm2s_byte_matches;
    int unsigned mm2s_byte_mismatches;
    int unsigned mm2s_pkt_errors;
    int unsigned mm2s_addr_errors;
    int unsigned mm2s_status_mismatches;
    int unsigned mm2s_hang_count;

    int unsigned s2mm_cmd_count;
    int unsigned s2mm_status_count;
    int unsigned s2mm_bytes_checked;
    int unsigned s2mm_byte_matches;
    int unsigned s2mm_byte_mismatches;
    int unsigned s2mm_len_mismatches;
    int unsigned s2mm_pkt_errors;
    int unsigned s2mm_addr_errors;
    int unsigned s2mm_status_mismatches;
    int unsigned s2mm_hang_count;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    function new(string name = "dma_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        imp_dma_rd_cmd    = new("imp_dma_rd_cmd",    this);
        imp_dma_rd_status = new("imp_dma_rd_status", this);
        imp_dma_wr_cmd    = new("imp_dma_wr_cmd",    this);
        imp_dma_wr_status = new("imp_dma_wr_status", this);
        imp_axis_rd       = new("imp_axis_rd",       this);
        imp_axis_wr       = new("imp_axis_wr",       this);
        imp_axi_rd        = new("imp_axi_rd",        this);
        imp_axi_wr        = new("imp_axi_wr",        this);

        mm2s_cmd_count         = 0;
        mm2s_status_count      = 0;
        mm2s_bytes_checked     = 0;
        mm2s_byte_matches      = 0;
        mm2s_byte_mismatches   = 0;
        mm2s_pkt_errors        = 0;
        mm2s_addr_errors       = 0;
        mm2s_status_mismatches = 0;
        mm2s_hang_count        = 0;

        s2mm_cmd_count         = 0;
        s2mm_status_count      = 0;
        s2mm_bytes_checked     = 0;
        s2mm_byte_matches      = 0;
        s2mm_byte_mismatches   = 0;
        s2mm_len_mismatches    = 0;
        s2mm_pkt_errors        = 0;
        s2mm_addr_errors       = 0;
        s2mm_status_mismatches = 0;
        s2mm_hang_count        = 0;
    endfunction : new

    // =========================================================================
    // 4. MM2S Checking Engine (Memory -> Stream)
    // =========================================================================

    // 4.1. MM2S Read Command Ingestion
    virtual function void write_dma_rd_cmd(dma_desc_item_type t);
        mm2s_txn_type desc = new();
        desc.start_addr               = t.addr;
        desc.xfer_len                 = t.len;
        desc.tag                      = t.tag;
        desc.total_bytes_expected     = t.len;
        desc.expected_next_burst_addr = t.addr & ~(STRB_WIDTH - 1);
        desc.cmd_seen                 = 1'b1;

        mm2s_queue.push_back(desc);
        mm2s_by_tag[t.tag] = desc;
        mm2s_cmd_count++;

        `uvm_info("SCB_MM2S_CMD", $sformatf("Registered MM2S Read Descriptor: tag=0x%02h, addr=0x%04h, len=%0d bytes",
                  t.tag, t.addr, t.len), UVM_MEDIUM)
    endfunction : write_dma_rd_cmd

    // 4.2. MM2S Memory Read Snooping (Source Truth & Address Progression)
    virtual function void write_axi_rd(axi_item_type t);
        mm2s_txn_type desc;

        if (mm2s_queue.size() == 0) begin
            `uvm_error("SCB_MM2S_UNEXP_RD", $sformatf("Observed AXI Read burst (addr=0x%04h) without active MM2S descriptor!", t.addr))
            return;
        end

        desc = mm2s_queue[0];

        // Verify AXI Read burst address progression
        if (t.addr !== desc.expected_next_burst_addr) begin
            `uvm_error("SCB_MM2S_BURST_ADDR", $sformatf("MM2S AXI Read burst address mismatch for tag 0x%02h! Expected=0x%04h, Actual=0x%04h",
                       desc.tag, desc.expected_next_burst_addr, t.addr))
            mm2s_addr_errors++;
        end
        desc.expected_next_burst_addr += ((t.len + 1) * STRB_WIDTH);

        // Unpack 32-bit read data words into individual byte stream
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

    // 4.3. MM2S Egress Stream Verification (Destination Stream Sink & Packet Framing)
    virtual function void write_axis_rd(axis_item_type t);
        mm2s_txn_type desc;
        int unsigned pkt_bytes = 0;

        if (mm2s_queue.size() == 0) begin
            `uvm_error("SCB_MM2S_UNEXP_STREAM", "Observed egress stream packet on AXIS without active MM2S descriptor!")
            return;
        end

        desc = mm2s_queue[0];

        // Count packet payload bytes across all beats
        for (int beat = 0; beat < t.data.size(); beat++) begin
            for (int lane = 0; lane < STRB_WIDTH; lane++) begin
                if (t.keep[beat][lane]) begin
                    byte act_byte = (t.data[beat] >> (8 * lane)) & 8'hFF;
                    desc.actual_bytes.push_back(act_byte);
                    pkt_bytes++;
                end
            end
        end

        // [P1 Fix] Check 1-to-1 packet boundary framing per descriptor
        if (desc.packet_count > 0) begin
            `uvm_error("SCB_MM2S_EXTRA_PKT", $sformatf("MM2S descriptor tag 0x%02h produced multiple stream packets! (packet #%0d)",
                       desc.tag, desc.packet_count + 1))
            mm2s_pkt_errors++;
        end

        // [P1 Fix] Verify packet length at TLAST matches descriptor requested length
        if (pkt_bytes != desc.xfer_len) begin
            `uvm_error("SCB_MM2S_PKT_LEN", $sformatf("MM2S Stream packet terminated with TLAST at %0d bytes, but descriptor requested %0d bytes! (tag 0x%02h)",
                       pkt_bytes, desc.xfer_len, desc.tag))
            mm2s_pkt_errors++;
        end

        desc.packet_count++;
        desc.stream_pkt_bytes = pkt_bytes;
        desc.stream_done      = 1'b1;

        compare_mm2s_data(desc);
    endfunction : write_axis_rd

    // 4.4. MM2S Incremental Pair-Wise Data Comparator
    virtual function void compare_mm2s_data(mm2s_txn_type desc);
        while (desc.expected_bytes.size() > 0 && desc.actual_bytes.size() > 0) begin
            byte exp_b = desc.expected_bytes.pop_front();
            byte act_b = desc.actual_bytes.pop_front();
            mm2s_bytes_checked++;

            if (exp_b === act_b) begin
                mm2s_byte_matches++;
                desc.bytes_matched++;
            end else begin
                mm2s_byte_mismatches++;
                `uvm_error("SCB_MM2S_DATA_MISMATCH", $sformatf("MM2S Data Mismatch at byte %0d for tag 0x%02h: Expected=0x%02h, Actual=0x%02h",
                           desc.bytes_matched, desc.tag, exp_b, act_b))
            end
        end
    endfunction : compare_mm2s_data

    // 4.5. MM2S Completion Status Verification
    virtual function void write_dma_rd_status(dma_desc_item_type t);
        mm2s_txn_type desc;
        int found_idx = -1;
        mm2s_status_count++;

        if (!mm2s_by_tag.exists(t.status_tag)) begin
            `uvm_error("SCB_MM2S_UNEXP_TAG", $sformatf("MM2S Status returned unknown tag: 0x%02h", t.status_tag))
            mm2s_status_mismatches++;
            return;
        end

        desc = mm2s_by_tag[t.status_tag];
        desc.status_done = 1'b1;

        // [P2 Fix] Check in-order completion assertion for the single-pipeline MM2S engine
        if (mm2s_queue.size() > 0 && mm2s_queue[0].tag !== t.status_tag) begin
            `uvm_error("SCB_MM2S_OOO", $sformatf("MM2S completion status tag 0x%02h arrived out-of-order! Expected queue head tag 0x%02h",
                       t.status_tag, mm2s_queue[0].tag))
            mm2s_status_mismatches++;
        end

        // [P1 Fix] Verify that a complete stream packet (TLAST) was observed before status completion
        if (desc.packet_count == 0) begin
            `uvm_error("SCB_MM2S_NO_PKT", $sformatf("MM2S status reported for tag 0x%02h, but no stream packet (TLAST) was observed!", t.status_tag))
            mm2s_pkt_errors++;
        end

        // Drain any remaining bytes
        compare_mm2s_data(desc);

        // Verify total byte count matched descriptor transfer length
        if (desc.bytes_matched != desc.xfer_len) begin
            `uvm_error("SCB_MM2S_LEN_MISMATCH", $sformatf("MM2S Length mismatch for tag 0x%02h: Expected=%0d bytes, Verified=%0d bytes",
                       t.status_tag, desc.xfer_len, desc.bytes_matched))
            mm2s_status_mismatches++;
        end

        // Verify no leftover unmatched bytes
        if (desc.expected_bytes.size() != 0) begin
            `uvm_error("SCB_MM2S_ORPHAN_EXP", $sformatf("MM2S Tag 0x%02h completed with %0d unconsumed expected bytes!",
                       t.status_tag, desc.expected_bytes.size()))
            mm2s_status_mismatches++;
        end
        if (desc.actual_bytes.size() != 0) begin
            `uvm_error("SCB_MM2S_ORPHAN_ACT", $sformatf("MM2S Tag 0x%02h completed with %0d uncompared actual stream bytes!",
                       t.status_tag, desc.actual_bytes.size()))
            mm2s_status_mismatches++;
        end

        // Verify completion status error code
        if (t.status_error != DMA_ERR_NONE) begin
            `uvm_error("SCB_MM2S_ERR", $sformatf("MM2S Descriptor tag 0x%02h completed with error code: %s (0x%0x)",
                       t.status_tag, t.status_error.name(), t.status_error))
            mm2s_status_mismatches++;
        end

        // [P2 Fix] Clean up completed descriptor by tag across both lookup structures
        foreach (mm2s_queue[i]) begin
            if (mm2s_queue[i].tag == t.status_tag) begin
                found_idx = i;
                break;
            end
        end
        if (found_idx >= 0) begin
            mm2s_queue.delete(found_idx);
        end
        mm2s_by_tag.delete(t.status_tag);

        `uvm_info("SCB_MM2S_PASS", $sformatf("MM2S Transfer Complete & Verified: tag=0x%02h, len=%0d bytes",
                  t.status_tag, desc.bytes_matched), UVM_LOW)
    endfunction : write_dma_rd_status

    // =========================================================================
    // 5. S2MM Checking Engine (Stream -> Memory)
    // =========================================================================

    // 5.1. S2MM Write Command Ingestion
    virtual function void write_dma_wr_cmd(dma_desc_item_type t);
        s2mm_txn_type desc = new();
        desc.dest_addr                 = t.addr;
        desc.buffer_len                = t.len;
        desc.tag                       = t.tag;
        desc.expected_next_byte_addr   = t.addr;
        desc.expected_next_burst_addr  = t.addr & ~(STRB_WIDTH - 1);
        desc.first_burst_seen          = 1'b0;
        desc.cmd_seen                  = 1'b1;

        s2mm_queue.push_back(desc);
        s2mm_by_tag[t.tag] = desc;
        s2mm_cmd_count++;

        `uvm_info("SCB_S2MM_CMD", $sformatf("Registered S2MM Write Descriptor: tag=0x%02h, addr=0x%04h, buffer_len=%0d bytes",
                  t.tag, t.addr, t.len), UVM_MEDIUM)
    endfunction : write_dma_wr_cmd

    // 5.2. S2MM Ingress Stream Ingestion (Source Truth Payload & Packet Framing)
    virtual function void write_axis_wr(axis_item_type t);
        s2mm_txn_type desc;
        int unsigned pkt_bytes = 0;

        if (s2mm_queue.size() == 0) begin
            `uvm_error("SCB_S2MM_UNEXP_STREAM", "Observed ingress stream packet on AXIS without active S2MM descriptor!")
            return;
        end

        desc = s2mm_queue[0];

        // [P1 Fix] Check 1-to-1 packet boundary framing per descriptor
        if (desc.packet_count > 0) begin
            `uvm_error("SCB_S2MM_EXTRA_PKT", $sformatf("S2MM descriptor tag 0x%02h received multiple ingress stream packets! (packet #%0d)",
                       desc.tag, desc.packet_count + 1))
            s2mm_pkt_errors++;
        end

        // Collect all active stream payload bytes
        for (int beat = 0; beat < t.data.size(); beat++) begin
            for (int lane = 0; lane < STRB_WIDTH; lane++) begin
                if (t.keep[beat][lane]) begin
                    byte stream_b = (t.data[beat] >> (8 * lane)) & 8'hFF;
                    desc.stream_in_bytes.push_back(stream_b);
                    desc.total_stream_bytes++;
                    pkt_bytes++;
                end
            end
        end

        desc.packet_count++;
        desc.stream_pkt_bytes = pkt_bytes;
        desc.stream_done      = 1'b1;

        compare_s2mm_data(desc);
    endfunction : write_axis_wr

    // 5.3. S2MM Memory Write Verification (Address Progression & Strobe Placement)
    virtual function void write_axi_wr(axi_item_type t);
        s2mm_txn_type desc;

        if (s2mm_queue.size() == 0) begin
            `uvm_error("SCB_S2MM_UNEXP_WR", $sformatf("Observed AXI Write burst (addr=0x%04h) without active S2MM descriptor!", t.addr))
            return;
        end

        desc = s2mm_queue[0];

        // [P1 Fix] Verify AXI Write burst address progression across ALL bursts
        if (t.addr !== desc.expected_next_burst_addr) begin
            `uvm_error("SCB_S2MM_BURST_ADDR", $sformatf("S2MM AXI Write burst address mismatch for tag 0x%02h! Expected=0x%04h, Actual=0x%04h",
                       desc.tag, desc.expected_next_burst_addr, t.addr))
            s2mm_addr_errors++;
        end
        desc.expected_next_burst_addr += ((t.len + 1) * STRB_WIDTH);
        desc.first_burst_seen = 1'b1;

        // [P1 Fix] Unpack write burst beats and verify byte address and strobe placement
        for (int i = 0; i <= t.len; i++) begin
            for (int b = 0; b < STRB_WIDTH; b++) begin
                bit [ADDR_WIDTH-1:0] lane_addr = (t.addr & ~(STRB_WIDTH - 1)) + (i * STRB_WIDTH) + b;
                if (t.strb[i][b]) begin
                    // Active strobe lane: must match expected sequential memory byte address
                    if (lane_addr !== desc.expected_next_byte_addr) begin
                        `uvm_error("SCB_S2MM_BYTE_ADDR", $sformatf("S2MM Active WSTRB at unexpected memory address! Expected=0x%04h, lane_addr=0x%04h (burst=0x%04h, beat=%0d, lane=%0d, tag 0x%02h)",
                                   desc.expected_next_byte_addr, lane_addr, t.addr, i, b, desc.tag))
                        s2mm_addr_errors++;
                    end
                    byte act_byte = (t.data[i] >> (8 * b)) & 8'hFF;
                    desc.axi_wr_bytes.push_back(act_byte);
                    desc.expected_next_byte_addr++;
                end else begin
                    // Inactive strobe lane: verify that inactive strobes only occur outside payload boundaries
                    // (e.g. unaligned start offset on first beat or tail offset on last beat)
                    if (desc.first_burst_seen && lane_addr >= desc.dest_addr && lane_addr < desc.expected_next_byte_addr) begin
                        `uvm_error("SCB_S2MM_GAP_STRB", $sformatf("S2MM WSTRB gap detected at address 0x%04h inside payload window (burst=0x%04h, beat=%0d, lane=%0d)",
                                   lane_addr, t.addr, i, b))
                        s2mm_addr_errors++;
                    end
                end
            end
        end

        compare_s2mm_data(desc);
    endfunction : write_axi_wr

    // 5.4. S2MM Incremental Pair-Wise Data Comparator
    virtual function void compare_s2mm_data(s2mm_txn_type desc);
        while (desc.stream_in_bytes.size() > 0 && desc.axi_wr_bytes.size() > 0) begin
            byte exp_b = desc.stream_in_bytes.pop_front();
            byte act_b = desc.axi_wr_bytes.pop_front();
            s2mm_bytes_checked++;

            if (exp_b === act_b) begin
                s2mm_byte_matches++;
                desc.bytes_matched++;
            end else begin
                s2mm_byte_mismatches++;
                `uvm_error("SCB_S2MM_DATA_MISMATCH", $sformatf("S2MM Data Mismatch at byte %0d for tag 0x%02h: Expected=0x%02h, Actual=0x%02h",
                           desc.bytes_matched, desc.tag, exp_b, act_b))
            end
        end
    endfunction : compare_s2mm_data

    // 5.5. S2MM Completion Status Verification
    virtual function void write_dma_wr_status(dma_desc_item_type t);
        s2mm_txn_type desc;
        int found_idx = -1;
        s2mm_status_count++;

        if (!s2mm_by_tag.exists(t.status_tag)) begin
            `uvm_error("SCB_S2MM_UNEXP_TAG", $sformatf("S2MM Status returned unknown tag: 0x%02h", t.status_tag))
            s2mm_status_mismatches++;
            return;
        end

        desc = s2mm_by_tag[t.status_tag];
        desc.status_done = 1'b1;

        // [P2 Fix] Check in-order completion assertion for the single-pipeline S2MM engine
        if (s2mm_queue.size() > 0 && s2mm_queue[0].tag !== t.status_tag) begin
            `uvm_error("SCB_S2MM_OOO", $sformatf("S2MM completion status tag 0x%02h arrived out-of-order! Expected queue head tag 0x%02h",
                       t.status_tag, s2mm_queue[0].tag))
            s2mm_status_mismatches++;
        end

        // [P1 Fix] Verify that a complete stream packet was observed before status completion
        if (desc.packet_count == 0) begin
            `uvm_error("SCB_S2MM_NO_PKT", $sformatf("S2MM status reported for tag 0x%02h, but no ingress stream packet was observed!", t.status_tag))
            s2mm_pkt_errors++;
        end

        // Drain any remaining bytes
        compare_s2mm_data(desc);

        // Verify status_len accurately reflects the number of transferred stream bytes
        if (t.status_len !== desc.total_stream_bytes) begin
            `uvm_error("SCB_S2MM_LEN_MISMATCH", $sformatf("S2MM status_len mismatch for tag 0x%02h: Expected=%0d bytes, Reported=%0d bytes",
                       t.status_tag, desc.total_stream_bytes, t.status_len))
            s2mm_len_mismatches++;
        end

        // Verify all stream bytes reached memory
        if (desc.bytes_matched != desc.total_stream_bytes) begin
            `uvm_error("SCB_S2MM_DATA_COUNT", $sformatf("S2MM matched bytes mismatch for tag 0x%02h: Streamed=%0d, Matched=%0d",
                       t.status_tag, desc.total_stream_bytes, desc.bytes_matched))
            s2mm_len_mismatches++;
        end

        // Verify no leftover unmatched bytes
        if (desc.stream_in_bytes.size() != 0) begin
            `uvm_error("SCB_S2MM_ORPHAN_STREAM", $sformatf("S2MM Tag 0x%02h completed with %0d unwritten stream bytes!",
                       t.status_tag, desc.stream_in_bytes.size()))
            s2mm_len_mismatches++;
        end
        if (desc.axi_wr_bytes.size() != 0) begin
            `uvm_error("SCB_S2MM_ORPHAN_MEM", $sformatf("S2MM Tag 0x%02h completed with %0d uncompared memory write bytes!",
                       t.status_tag, desc.axi_wr_bytes.size()))
            s2mm_byte_mismatches++;
        end

        // Verify status error code
        if (t.status_error != DMA_ERR_NONE) begin
            `uvm_error("SCB_S2MM_ERR", $sformatf("S2MM Descriptor tag 0x%02h completed with error code: %s (0x%0x)",
                       t.status_tag, t.status_error.name(), t.status_error))
            s2mm_status_mismatches++;
        end

        // [P2 Fix] Clean up completed descriptor by tag across both lookup structures
        foreach (s2mm_queue[i]) begin
            if (s2mm_queue[i].tag == t.status_tag) begin
                found_idx = i;
                break;
            end
        end
        if (found_idx >= 0) begin
            s2mm_queue.delete(found_idx);
        end
        s2mm_by_tag.delete(t.status_tag);

        `uvm_info("SCB_S2MM_PASS", $sformatf("S2MM Transfer Complete & Verified: tag=0x%02h, len=%0d bytes",
                  t.status_tag, t.status_len), UVM_LOW)
    endfunction : write_dma_wr_status

    // =========================================================================
    // 6. End-of-Test Cleanliness Check
    // =========================================================================
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        mm2s_hang_count = mm2s_queue.size();
        s2mm_hang_count = s2mm_queue.size();

        if (mm2s_hang_count != 0) begin
            `uvm_error("SCB_MM2S_HANG", $sformatf("End of Test Cleanliness: %0d MM2S descriptor(s) never completed! Head tag=0x%02h",
                       mm2s_hang_count, mm2s_queue[0].tag))
        end

        if (s2mm_hang_count != 0) begin
            `uvm_error("SCB_S2MM_HANG", $sformatf("End of Test Cleanliness: %0d S2MM descriptor(s) never completed! Head tag=0x%02h",
                       s2mm_hang_count, s2mm_queue[0].tag))
        end
    endfunction : check_phase

    // =========================================================================
    // 7. Authoritative Scorecard Summary Report
    // =========================================================================
    virtual function void report_phase(uvm_phase phase);
        bit has_errors;
        super.report_phase(phase);

        // [P2 Fix] Incorporate outstanding queues, packet errors, and address errors into verdict
        has_errors = (mm2s_byte_mismatches > 0) || (mm2s_status_mismatches > 0) ||
                     (s2mm_byte_mismatches > 0) || (s2mm_len_mismatches > 0)    || (s2mm_status_mismatches > 0) ||
                     (mm2s_pkt_errors > 0)      || (s2mm_pkt_errors > 0)        ||
                     (mm2s_addr_errors > 0)     || (s2mm_addr_errors > 0)       ||
                     (mm2s_hang_count > 0)      || (s2mm_hang_count > 0)        ||
                     (mm2s_queue.size() > 0)    || (s2mm_queue.size() > 0)      ||
                     (mm2s_by_tag.num() > 0)    || (s2mm_by_tag.num() > 0);

        `uvm_info("SCB_REPORT", "========================================================================================================================", UVM_NONE)
        `uvm_info("SCB_REPORT", "                                            AXI4 DMA SCOREBOARD FINAL REPORT                                            ", UVM_NONE)
        `uvm_info("SCB_REPORT", "========================================================================================================================", UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf(" MM2S Pipeline : Cmds=%0d, Done=%0d, Bytes=%0d, Matches=%0d, Mismatches=%0d, PktErr=%0d, AddrErr=%0d, StatusErr=%0d, Hung=%0d",
                  mm2s_cmd_count, mm2s_status_count, mm2s_bytes_checked, mm2s_byte_matches, mm2s_byte_mismatches, mm2s_pkt_errors, mm2s_addr_errors, mm2s_status_mismatches, mm2s_hang_count), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf(" S2MM Pipeline : Cmds=%0d, Done=%0d, Bytes=%0d, Matches=%0d, Mismatches=%0d, LenErr=%0d, PktErr=%0d, AddrErr=%0d, StatusErr=%0d, Hung=%0d",
                  s2mm_cmd_count, s2mm_status_count, s2mm_bytes_checked, s2mm_byte_matches, s2mm_byte_mismatches, s2mm_len_mismatches, s2mm_pkt_errors, s2mm_addr_errors, s2mm_status_mismatches, s2mm_hang_count), UVM_NONE)
        `uvm_info("SCB_REPORT", "------------------------------------------------------------------------------------------------------------------------", UVM_NONE)

        if (!has_errors && (mm2s_cmd_count > 0 || s2mm_cmd_count > 0)) begin
            `uvm_info("SCB_REPORT", " >>> OVERALL SCOREBOARD VERDICT: [TEST PASSED] - 100% Data, Framing & Status Match <<<                                 ", UVM_NONE)
        end else if (has_errors) begin
            `uvm_error("SCB_REPORT", " >>> OVERALL SCOREBOARD VERDICT: [TEST FAILED] - Data Mismatches, Framing Errors, or Hung Transfers Detected! <<<")
        end else begin
            `uvm_warning("SCB_REPORT", " >>> OVERALL SCOREBOARD VERDICT: [NO TRANSFERS OBSERVED] <<<                                                                ")
        end
        `uvm_info("SCB_REPORT", "========================================================================================================================", UVM_NONE)
    endfunction : report_phase

endclass : dma_scoreboard

`endif // DMA_SCOREBOARD_SV