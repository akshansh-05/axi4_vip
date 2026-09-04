// File: axi_scoreboard.sv
// Scoreboard for AXI4 Memory-Mapped bus verification.
// Maintains an associative reference memory model, processes write bursts with byte strobes,
// compares read bursts against expected memory contents, and prints a final verification scorecard.

`ifndef AXI_SCOREBOARD_SV
`define AXI_SCOREBOARD_SV

class axi_scoreboard #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_scoreboard;

    typedef axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) item_type;

    `uvm_component_param_utils(axi_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    // Analysis export receiving transactions broadcast by axi_monitor
    uvm_analysis_imp #(item_type, axi_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH)) analysis_export;

    // Associative reference memory model (byte-level addressing)
    bit [7:0] ref_mem [bit [ADDR_WIDTH-1:0]];

    // Scoreboard statistical counters
    int unsigned write_count;
    int unsigned read_count;
    int unsigned match_count;
    int unsigned mismatch_count;

    function new(string name = "axi_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        analysis_export = new("analysis_export", this);
        write_count    = 0;
        read_count     = 0;
        match_count    = 0;
        mismatch_count = 0;
    endfunction : new

    // Main analysis write method called whenever monitor broadcasts a completed transaction
    virtual function void write(item_type txn);
        if (txn.trans_type == AXI_WRITE) begin
            process_write(txn);
        end else begin
            process_read(txn);
        end
    endfunction : write

    // Computes target byte address for a specific burst beat
    virtual function bit [ADDR_WIDTH-1:0] calculate_beat_addr(
        bit [ADDR_WIDTH-1:0] start_addr,
        bit [7:0]            len,
        bit [2:0]            size,
        axi_burst_type_e     burst,
        int                  beat_idx
    );
        int num_bytes;
        num_bytes = 1 << size;

        case (burst)
            AXI_BURST_FIXED: begin
                return start_addr;
            end

            AXI_BURST_INCR: begin
                return start_addr + (beat_idx * num_bytes);
            end

            AXI_BURST_WRAP: begin
                int wrap_boundary;
                int total_bytes;
                total_bytes   = (len + 1) * num_bytes;
                wrap_boundary = (start_addr / total_bytes) * total_bytes;
                return wrap_boundary + ((start_addr + (beat_idx * num_bytes)) % total_bytes);
            end

            default: begin
                return start_addr + (beat_idx * num_bytes);
            end
        endcase
    endfunction : calculate_beat_addr

    // Updates reference memory for write transactions taking byte strobes into account
    virtual function void process_write(item_type txn);
        write_count++;
        `uvm_info("SCB_WR", $sformatf("Processing Write Burst #%0d: addr=0x%04h, len=%0d beats, size=%0d bytes",
                  write_count, txn.addr, txn.len + 1, (1 << txn.size)), UVM_HIGH)

        for (int i = 0; i <= txn.len; i++) begin
            bit [ADDR_WIDTH-1:0] beat_addr;
            beat_addr = calculate_beat_addr(txn.addr, txn.len, txn.size, txn.burst, i);

            for (int b = 0; b < STRB_WIDTH; b++) begin
                if (txn.strb[i][b]) begin
                    bit [7:0] byte_val;
                    byte_val = (txn.data[i] >> (b * 8)) & 8'hFF;
                    ref_mem[beat_addr + b] = byte_val;
                    `uvm_info("SCB_MEM_WR", $sformatf("  [RefMem] Write addr=0x%04h <= 0x%02h",
                              beat_addr + b, byte_val), UVM_FULL)
                end
            end
        end
    endfunction : process_write

    // Compares actual read burst data from DUT against expected reference memory contents
    virtual function void process_read(item_type txn);
        read_count++;
        `uvm_info("SCB_RD", $sformatf("Processing Read Burst #%0d: addr=0x%04h, len=%0d beats, size=%0d bytes",
                  read_count, txn.addr, txn.len + 1, (1 << txn.size)), UVM_HIGH)

        for (int i = 0; i <= txn.len; i++) begin
            bit [ADDR_WIDTH-1:0] beat_addr;
            bit [DATA_WIDTH-1:0] expected_data;
            bit [DATA_WIDTH-1:0] actual_data;

            beat_addr     = calculate_beat_addr(txn.addr, txn.len, txn.size, txn.burst, i);
            expected_data = '0;
            actual_data   = txn.data[i];

            for (int b = 0; b < STRB_WIDTH; b++) begin
                bit [7:0] expected_byte;
                if (ref_mem.exists(beat_addr + b)) begin
                    expected_byte = ref_mem[beat_addr + b];
                end else begin
                    expected_byte = 8'h00; // Uninitialized memory defaults to 0
                end
                expected_data |= (bit [DATA_WIDTH-1:0]'(expected_byte) << (b * 8));
            end

            // Compare expected vs actual read data
            if (actual_data === expected_data) begin
                match_count++;
                `uvm_info("SCB_PASS", $sformatf("Beat [%0d/%0d] ADDR 0x%04h MATCH: Expected=0x%08h Actual=0x%08h",
                          i, txn.len, beat_addr, expected_data, actual_data), UVM_MEDIUM)
            end else begin
                mismatch_count++;
                `uvm_error("SCB_FAIL", $sformatf("Beat [%0d/%0d] ADDR 0x%04h MISMATCH: Expected=0x%08h Actual=0x%08h (Diff=0x%08h)",
                           i, txn.len, beat_addr, expected_data, actual_data, (expected_data ^ actual_data)))
            end
        end
    endfunction : process_read

    // Final summary report at end of simulation
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCOREBOARD", "--------------------------------------------------------", UVM_LOW)
        `uvm_info("SCOREBOARD", "               AXI SCOREBOARD SUMMARY REPORT            ", UVM_LOW)
        `uvm_info("SCOREBOARD", "--------------------------------------------------------", UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf("  Total Write Transactions Processed : %0d", write_count), UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf("  Total Read Transactions Processed  : %0d", read_count), UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf("  Total Read Beat Matches (PASS)     : %0d", match_count), UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf("  Total Read Beat Mismatches (FAIL)  : %0d", mismatch_count), UVM_LOW)
        `uvm_info("SCOREBOARD", "--------------------------------------------------------", UVM_LOW)

        if (mismatch_count == 0 && match_count > 0) begin
            `uvm_info("SCOREBOARD", "  STATUS: *** TEST PASSED (100% DATA INTEGRITY) ***", UVM_LOW)
        end else if (mismatch_count > 0) begin
            `uvm_error("SCOREBOARD", "  STATUS: *** TEST FAILED WITH MISMATCHES ***")
        end else begin
            `uvm_warning("SCOREBOARD", "  STATUS: NO READ COMPARISONS WERE PERFORMED")
        end
        `uvm_info("SCOREBOARD", "--------------------------------------------------------", UVM_LOW)
    endfunction : report_phase

endclass : axi_scoreboard

`endif // AXI_SCOREBOARD_SV
