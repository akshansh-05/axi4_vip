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

// Helper Descriptor Tracking Class for MM2S
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
    dma_error_e          status_error;

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
        status_error              = DMA_ERR_NONE;
    endfunction
endclass : mm2s_desc_txn

// Top DMA Scoreboard Component (MM2S Read Engine Focus)
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

    // 1. Analysis Exports (MM2S Ports)
    uvm_analysis_imp_dma_rd_cmd    #(dma_desc_item_type, dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_dma_rd_cmd;
    uvm_analysis_imp_dma_rd_status #(dma_desc_item_type, dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_dma_rd_status;
    uvm_analysis_imp_axis_rd       #(axis_item_type,     dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_axis_rd;
    uvm_analysis_imp_axi_rd        #(axi_item_type,      dma_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH)) imp_axi_rd;

    // 2. Internal Tracking Data Structures
    mm2s_txn_type mm2s_queue[$];
    mm2s_txn_type mm2s_by_tag[bit [TAG_WIDTH-1:0]];

    // 3. Verification Statistics
    int unsigned mm2s_cmd_count          = 0;
    int unsigned mm2s_status_count       = 0;
    int unsigned mm2s_bytes_checked      = 0;
    int unsigned mm2s_byte_matches       = 0;
    int unsigned mm2s_byte_mismatches    = 0;
    int unsigned mm2s_pkt_errors         = 0;
    int unsigned mm2s_addr_errors        = 0;
    int unsigned mm2s_status_mismatches  = 0;
    int unsigned mm2s_hang_count         = 0;

    // Constructor
    function new(string name = "dma_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        imp_dma_rd_cmd    = new("imp_dma_rd_cmd", this);
        imp_dma_rd_status = new("imp_dma_rd_status", this);
        imp_axis_rd       = new("imp_axis_rd", this);
        imp_axi_rd        = new("imp_axi_rd", this);
    endfunction : new

    // Stage 1: Command Registration (dma_rd_desc_monitor -> cmd_ap)
    virtual function void write_dma_rd_cmd(dma_desc_item_type t);
        mm2s_txn_type desc;

        desc = new();
        desc.start_addr               = t.addr;
        desc.xfer_len                 = t.len;
        desc.tag                      = t.tag;
        desc.total_bytes_expected     = t.len;
        desc.expected_next_burst_addr = t.addr;
        desc.cmd_seen                 = 1'b1;

        mm2s_queue.push_back(desc);
        mm2s_by_tag[t.tag] = desc;
        mm2s_cmd_count++;

        `uvm_info("SCB_MM2S_CMD", $sformatf("Registered MM2S Read Descriptor: tag=0x%02h, addr=0x%04h, len=%0d bytes",
                  t.tag, t.addr, t.len), UVM_MEDIUM)
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
            `uvm_error("SCB_MM2S_BURST_ADDR", $sformatf("MM2S AXI Read burst address mismatch for tag 0x%02h! Expected=0x%04h, Actual=0x%04h",
                       desc.tag, desc.expected_next_burst_addr, t.addr))
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
            `uvm_error("SCB_MM2S_EXTRA_PKT", $sformatf("MM2S descriptor tag 0x%02h produced multiple stream packets! (packet #%0d)",
                       desc.tag, desc.packet_count + 1))
            mm2s_pkt_errors++;
        end

        // 3. Verify packet length at TLAST matches descriptor requested length
        if (pkt_bytes != desc.xfer_len) begin
            `uvm_error("SCB_MM2S_PKT_LEN", $sformatf("MM2S Stream packet terminated with TLAST at %0d bytes, but descriptor requested %0d bytes! (tag 0x%02h)",
                       pkt_bytes, desc.xfer_len, desc.tag))
            mm2s_pkt_errors++;
        end

        desc.packet_count++;
        desc.stream_pkt_bytes = pkt_bytes;
        desc.stream_done      = 1'b1;

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
            end else begin
                mm2s_byte_mismatches++;
                `uvm_error("SCB_MM2S_DATA_MISMATCH", $sformatf("MM2S Data Mismatch at byte %0d for tag 0x%02h: Expected=0x%02h, Actual=0x%02h",
                           desc.bytes_matched, desc.tag, exp_b, act_b))
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
        desc.status_done  = 1'b1;
        desc.status_error = t.status_error;

        // Check in-order completion assertion for the single-pipeline MM2S engine
        if (mm2s_queue.size() > 0 && mm2s_queue[0].tag !== t.status_tag) begin
            `uvm_error("SCB_MM2S_OOO", $sformatf("MM2S completion status tag 0x%02h arrived out-of-order! Expected queue head tag 0x%02h",
                       t.status_tag, mm2s_queue[0].tag))
            mm2s_status_mismatches++;
        end

        // If egress stream packet has already completed, retire descriptor now.
        // If stream packet is still draining through output FIFO, write_axis_rd will retire it.
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
            `uvm_error("SCB_MM2S_PKT_COUNT", $sformatf("MM2S descriptor tag 0x%02h expected 1 stream packet, but saw %0d!",
                       desc.tag, desc.packet_count))
            mm2s_pkt_errors++;
        end

        // 3. Verify total byte count matched descriptor transfer length
        if (desc.bytes_matched != desc.xfer_len) begin
            `uvm_error("SCB_MM2S_LEN_MISMATCH", $sformatf("MM2S Length mismatch for tag 0x%02h: Expected=%0d bytes, Verified=%0d bytes",
                       desc.tag, desc.xfer_len, desc.bytes_matched))
            mm2s_status_mismatches++;
        end

        // 4. Verify no leftover unmatched bytes
        if (desc.expected_bytes.size() != 0) begin
            `uvm_error("SCB_MM2S_ORPHAN_EXP", $sformatf("MM2S Tag 0x%02h completed with %0d unconsumed expected bytes!",
                       desc.tag, desc.expected_bytes.size()))
            mm2s_status_mismatches++;
        end
        if (desc.actual_bytes.size() != 0) begin
            `uvm_error("SCB_MM2S_ORPHAN_ACT", $sformatf("MM2S Tag 0x%02h completed with %0d uncompared actual stream bytes!",
                       desc.tag, desc.actual_bytes.size()))
            mm2s_status_mismatches++;
        end

        // 5. Verify completion status error code
        if (desc.status_error != DMA_ERR_NONE) begin
            `uvm_error("SCB_MM2S_ERR", $sformatf("MM2S Descriptor tag 0x%02h completed with error code: %s (0x%0x)",
                       desc.tag, desc.status_error.name(), desc.status_error))
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

        `uvm_info("SCB_MM2S_PASS", $sformatf("MM2S Transfer Complete & Verified: tag=0x%02h, len=%0d bytes",
                  desc.tag, desc.bytes_matched), UVM_LOW)
    endfunction : check_and_retire_mm2s

    // End-of-Test Cleanliness Check
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        mm2s_hang_count = mm2s_queue.size();

        if (mm2s_hang_count != 0) begin
            `uvm_error("SCB_MM2S_HANG", $sformatf("End of Test Cleanliness: %0d MM2S descriptor(s) never completed! Head tag=0x%02h (stream_done=%0b, status_done=%0b)",
                       mm2s_hang_count, mm2s_queue[0].tag, mm2s_queue[0].stream_done, mm2s_queue[0].status_done))
        end
    endfunction : check_phase

    // Authoritative Scorecard Summary Report
    virtual function void report_phase(uvm_phase phase);
        bit has_errors;
        super.report_phase(phase);

        has_errors = (mm2s_byte_mismatches > 0) || (mm2s_status_mismatches > 0) ||
                     (mm2s_pkt_errors > 0)      || (mm2s_addr_errors > 0)       ||
                     (mm2s_hang_count > 0)      || (mm2s_queue.size() > 0)      ||
                     (mm2s_by_tag.num() > 0);

        `uvm_info("SCB_MM2S", "MM2S SCOREBOARD SUMMARY", UVM_NONE)
        `uvm_info("SCB_MM2S", $sformatf("Commands: %0d | Status Done: %0d | Hung: %0d",
                  mm2s_cmd_count, mm2s_status_count, mm2s_hang_count), UVM_NONE)
        `uvm_info("SCB_MM2S", $sformatf("Bytes Checked: %0d | Matches: %0d | Mismatches: %0d",
                  mm2s_bytes_checked, mm2s_byte_matches, mm2s_byte_mismatches), UVM_NONE)
        `uvm_info("SCB_MM2S", $sformatf("Packet Errors: %0d | Addr Errors: %0d | Status Errors: %0d",
                  mm2s_pkt_errors, mm2s_addr_errors, mm2s_status_mismatches), UVM_NONE)

        if (!has_errors && (mm2s_cmd_count > 0)) begin
            `uvm_info("SCB_MM2S", "VERDICT: [PASSED] MM2S transfer verified successfully.", UVM_NONE)
        end else if (has_errors) begin
            `uvm_error("SCB_MM2S", "VERDICT: [FAILED] Mismatches, framing errors, or hung transfers detected.")
        end else begin
            `uvm_warning("SCB_MM2S", "VERDICT: [NO TRANSFERS] No MM2S commands observed.")
        end
    endfunction : report_phase

endclass : dma_scoreboard

`endif // DMA_SCOREBOARD_SV