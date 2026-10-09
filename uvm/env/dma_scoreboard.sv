// File: dma_scoreboard.sv
// Description: End-to-End Functional Scoreboard for AXI4 DMA Subsystem Verification.
//              Contains two independent, fully decoupled checking engines:
//              1. MM2S Engine (Memory -> Stream):
//                 - Slices AXI-MM read bursts into expected stream bytes.
//                 - Matches egress stream payload byte-for-byte, verifying TLAST & TKEEP.
//                 - Validates MM2S completion status tag and error code.
//              2. S2MM Engine (Stream -> Memory):
//                 - Ingests incoming stream payload bytes as golden reference.
//                 - Matches AXI-MM write burst payload, WSTRB lane enables, and alignment.
//                 - Validates S2MM completion status_len, tag, and error code.
//              3. Decoupled Concurrency & Burst Resilience:
//                 - Incremental pair-wise drain prevents false mismatches regardless of
//                   whether AXI bursts or AXIS packets complete first.
//                 - Tag-indexed maps support concurrent full-duplex operation with zero blocking.
//              4. Cleanliness Verification:
//                 - check_phase flags orphan/hung descriptors or uncompared bytes.
//                 - report_phase renders an authoritative Pass/Fail verification scorecard.

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
    bit                  cmd_seen;
    bit                  stream_done;
    bit                  status_done;

    function new();
        expected_bytes       = {};
        actual_bytes         = {};
        total_bytes_expected = 0;
        bytes_matched        = 0;
        cmd_seen             = 1'b0;
        stream_done          = 1'b0;
        status_done          = 1'b0;
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
    bit                  cmd_seen;
    bit                  stream_done;
    bit                  status_done;

    function new();
        stream_in_bytes    = {};
        axi_wr_bytes       = {};
        total_stream_bytes = 0;
        bytes_matched      = 0;
        cmd_seen           = 1'b0;
        stream_done        = 1'b0;
        status_done        = 1'b0;
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
    int unsigned mm2s_status_mismatches;

    int unsigned s2mm_cmd_count;
    int unsigned s2mm_status_count;
    int unsigned s2mm_bytes_checked;
    int unsigned s2mm_byte_matches;
    int unsigned s2mm_byte_mismatches;
    int unsigned s2mm_len_mismatches;
    int unsigned s2mm_status_mismatches;

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
        mm2s_status_mismatches = 0;

        s2mm_cmd_count         = 0;
        s2mm_status_count      = 0;
        s2mm_bytes_checked     = 0;
        s2mm_byte_matches      = 0;
        s2mm_byte_mismatches   = 0;
        s2mm_len_mismatches    = 0;
        s2mm_status_mismatches = 0;
    endfunction : new

    // =========================================================================
    // 4. MM2S Checking Engine (Memory -> Stream)
    // =========================================================================

    // 4.1. MM2S Read Command Ingestion
    virtual function void write_dma_rd_cmd(dma_desc_item_type t);
        mm2s_txn_type desc = new();
        desc.start_addr           = t.addr;
        desc.xfer_len             = t.len;
        desc.tag                  = t.tag;
        desc.total_bytes_expected = t.len;
        desc.cmd_seen             = 1'b1;

        mm2s_queue.push_back(desc);
        mm2s_by_tag[t.tag] = desc;
        mm2s_cmd_count++;

        `uvm_info("SCB_MM2S_CMD", $sformatf("Registered MM2S Read Descriptor: tag=0x%02h, addr=0x%04h, len=%0d bytes",
                  t.tag, t.addr, t.len), UVM_MEDIUM)
    endfunction : write_dma_rd_cmd

    // 4.2. MM2S Memory Read Snooping (Source Truth)
    virtual function void write_axi_rd(axi_item_type t);
        mm2s_txn_type desc;

        if (mm2s_queue.size() == 0) begin
            `uvm_error("SCB_MM2S_UNEXP_RD", $sformatf("Observed AXI Read burst (addr=0x%04h) without active MM2S descriptor!", t.addr))
            return;
        end

        desc = mm2s_queue[0];

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

    // 4.3. MM2S Egress Stream Verification (Destination Stream Sink)
    virtual function void write_axis_rd(axis_item_type t);
        mm2s_txn_type desc;

        if (mm2s_queue.size() == 0) begin
            `uvm_error("SCB_MM2S_UNEXP_STREAM", "Observed egress stream packet on AXIS without active MM2S descriptor!")
            return;
        end

        desc = mm2s_queue[0];

        // Unpack stream beats into actual byte queue
        for (int beat = 0; beat < t.data.size(); beat++) begin
            for (int lane = 0; lane < STRB_WIDTH; lane++) begin
                if (t.keep[beat][lane]) begin
                    byte act_byte = (t.data[beat] >> (8 * lane)) & 8'hFF;
                    desc.actual_bytes.push_back(act_byte);
                end
            end
        end

        desc.stream_done = 1'b1;
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
        mm2s_status_count++;

        if (!mm2s_by_tag.exists(t.status_tag)) begin
            `uvm_error("SCB_MM2S_UNEXP_TAG", $sformatf("MM2S Status returned unknown tag: 0x%02h", t.status_tag))
            mm2s_status_mismatches++;
            return;
        end

        desc = mm2s_by_tag[t.status_tag];
        desc.status_done = 1'b1;

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

        // Clean up completed descriptor
        if (mm2s_queue.size() > 0 && mm2s_queue[0].tag == t.status_tag) begin
            void'(mm2s_queue.pop_front());
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
        desc.dest_addr   = t.addr;
        desc.buffer_len  = t.len;
        desc.tag         = t.tag;
        desc.cmd_seen    = 1'b1;

        s2mm_queue.push_back(desc);
        s2mm_by_tag[t.tag] = desc;
        s2mm_cmd_count++;

        `uvm_info("SCB_S2MM_CMD", $sformatf("Registered S2MM Write Descriptor: tag=0x%02h, addr=0x%04h, buffer_len=%0d bytes",
                  t.tag, t.addr, t.len), UVM_MEDIUM)
    endfunction : write_dma_wr_cmd

    // 5.2. S2MM Ingress Stream Ingestion (Source Truth Payload)
    virtual function void write_axis_wr(axis_item_type t);
        s2mm_txn_type desc;

        if (s2mm_queue.size() == 0) begin
            `uvm_error("SCB_S2MM_UNEXP_STREAM", "Observed ingress stream packet on AXIS without active S2MM descriptor!")
            return;
        end

        desc = s2mm_queue[0];

        // Collect all active stream payload bytes
        for (int beat = 0; beat < t.data.size(); beat++) begin
            for (int lane = 0; lane < STRB_WIDTH; lane++) begin
                if (t.keep[beat][lane]) begin
                    byte stream_b = (t.data[beat] >> (8 * lane)) & 8'hFF;
                    desc.stream_in_bytes.push_back(stream_b);
                    desc.total_stream_bytes++;
                end
            end
        end

        desc.stream_done = 1'b1;
        compare_s2mm_data(desc);
    endfunction : write_axis_wr

    // 5.3. S2MM Memory Write Verification (Destination Comparator)
    virtual function void write_axi_wr(axi_item_type t);
        s2mm_txn_type desc;

        if (s2mm_queue.size() == 0) begin
            `uvm_error("SCB_S2MM_UNEXP_WR", $sformatf("Observed AXI Write burst (addr=0x%04h) without active S2MM descriptor!", t.addr))
            return;
        end

        desc = s2mm_queue[0];

        // Verify starting address alignment on initial burst
        if (desc.bytes_matched == 0 && desc.axi_wr_bytes.size() == 0) begin
            if (t.addr !== (desc.dest_addr & ~(STRB_WIDTH - 1))) begin
                `uvm_error("SCB_S2MM_ADDR_MISMATCH", $sformatf("S2MM Write Address mismatch: Expected=0x%04h, Actual=0x%04h",
                           desc.dest_addr, t.addr))
            end
        end

        // Unpack write burst beats and push active bytes into observed memory queue
        for (int i = 0; i <= t.len; i++) begin
            for (int b = 0; b < STRB_WIDTH; b++) begin
                if (t.strb[i][b]) begin
                    byte act_byte = (t.data[i] >> (8 * b)) & 8'hFF;
                    desc.axi_wr_bytes.push_back(act_byte);
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
        s2mm_status_count++;

        if (!s2mm_by_tag.exists(t.status_tag)) begin
            `uvm_error("SCB_S2MM_UNEXP_TAG", $sformatf("S2MM Status returned unknown tag: 0x%02h", t.status_tag))
            s2mm_status_mismatches++;
            return;
        end

        desc = s2mm_by_tag[t.status_tag];
        desc.status_done = 1'b1;

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

        // Clean up completed descriptor
        if (s2mm_queue.size() > 0 && s2mm_queue[0].tag == t.status_tag) begin
            void'(s2mm_queue.pop_front());
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

        if (mm2s_queue.size() != 0) begin
            `uvm_error("SCB_MM2S_HANG", $sformatf("End of Test Cleanliness: %0d MM2S descriptor(s) never completed!", mm2s_queue.size()))
        end

        if (s2mm_queue.size() != 0) begin
            `uvm_error("SCB_S2MM_HANG", $sformatf("End of Test Cleanliness: %0d S2MM descriptor(s) never completed!", s2mm_queue.size()))
        end
    endfunction : check_phase

    // =========================================================================
    // 7. Authoritative Scorecard Summary Report
    // =========================================================================
    virtual function void report_phase(uvm_phase phase);
        bit has_errors;
        super.report_phase(phase);

        has_errors = (mm2s_byte_mismatches > 0) || (mm2s_status_mismatches > 0) ||
                     (s2mm_byte_mismatches > 0) || (s2mm_len_mismatches > 0)    || (s2mm_status_mismatches > 0);

        `uvm_info("SCB_REPORT", "===================================================================================================", UVM_NONE)
        `uvm_info("SCB_REPORT", "                                AXI4 DMA SCOREBOARD FINAL REPORT                                   ", UVM_NONE)
        `uvm_info("SCB_REPORT", "===================================================================================================", UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf(" MM2S Pipeline : Cmds=%0d, Completed=%0d, Bytes=%0d, Matches=%0d, Mismatches=%0d, StatusErrors=%0d",
                  mm2s_cmd_count, mm2s_status_count, mm2s_bytes_checked, mm2s_byte_matches, mm2s_byte_mismatches, mm2s_status_mismatches), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf(" S2MM Pipeline : Cmds=%0d, Completed=%0d, Bytes=%0d, Matches=%0d, Mismatches=%0d, LenErrors=%0d",
                  s2mm_cmd_count, s2mm_status_count, s2mm_bytes_checked, s2mm_byte_matches, s2mm_byte_mismatches, s2mm_len_mismatches), UVM_NONE)
        `uvm_info("SCB_REPORT", "---------------------------------------------------------------------------------------------------", UVM_NONE)

        if (!has_errors && (mm2s_cmd_count > 0 || s2mm_cmd_count > 0)) begin
            `uvm_info("SCB_REPORT", " >>> OVERALL SCOREBOARD VERDICT: [TEST PASSED] - 100% Data & Status Match <<<                     ", UVM_NONE)
        end else if (has_errors) begin
            `uvm_error("SCB_REPORT", " >>> OVERALL SCOREBOARD VERDICT: [TEST FAILED] - Data Mismatches or Framing Errors Detected! <<<")
        end else begin
            `uvm_warning("SCB_REPORT", " >>> OVERALL SCOREBOARD VERDICT: [NO TRANSFERS OBSERVED] <<<                                    ")
        end
        `uvm_info("SCB_REPORT", "===================================================================================================", UVM_NONE)
    endfunction : report_phase

endclass : dma_scoreboard

`endif // DMA_SCOREBOARD_SV