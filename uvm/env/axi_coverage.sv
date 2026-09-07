// File: axi_coverage.sv
// Functional coverage subscriber for AXI4 Memory-Mapped bus (covering Write & Read channels).

`ifndef AXI_COVERAGE_SV
`define AXI_COVERAGE_SV

class axi_coverage #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_subscriber #(axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH));

    `uvm_component_param_utils(axi_coverage #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    typedef axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) item_type;

    // Transaction handle and per-beat strobe holder
    item_type            txn;
    bit [STRB_WIDTH-1:0] current_strb;

    // Latched burst attributes for per-beat cross-coverage correlation
    bit [7:0]            latched_awlen;
    bit [2:0]            latched_awsize;

    // =========================================================================
    // Covergroup: TRANSACTION-LEVEL Write Channels (AW, B)
    // Sampled ONCE per completed write burst to avoid statistical distortion.
    // =========================================================================
    covergroup cg_axi_write_xact;
        option.per_instance = 1;
        option.name = "cg_axi_write_xact";

        // 1. Write Burst Length (AWLEN: 0 to 255 beats)
        // Protocol Note (AXI4 Section A3.4.1): Beats = AWLEN + 1.
        // Bins len_2, len_4, len_8, len_16 are isolated specifically to match the 
        // strictly allowed wrapping burst lengths (2, 4, 8, 16 transfers).
        cp_awlen: coverpoint txn.len {
            bins single_beat = {0};                  // 1 beat transfer (AWLEN=0)
            bins len_2       = {1};                  // 2 beats  (AWLEN=1,  valid for WRAP/INCR/FIXED)
            bins len_4       = {3};                  // 4 beats  (AWLEN=3,  valid for WRAP/INCR/FIXED)
            bins len_8       = {7};                  // 8 beats  (AWLEN=7,  valid for WRAP/INCR/FIXED)
            bins len_16      = {15};                 // 16 beats (AWLEN=15, valid for WRAP/INCR/FIXED)
            bins other_short = {[2], [4:6], [8:14]}; // 3, 5..7, 9..15 beats (INCR & FIXED only, illegal for WRAP)
            bins med_burst   = {[16:63]};            // 17 to 64 beats (INCR only, illegal for FIXED & WRAP)
            bins long_burst  = {[64:254]};           // 65 to 255 beats (INCR only, illegal for FIXED & WRAP)
            bins max_burst   = {255};                // 256 beats (AXI4 max limit, INCR only)
        }

        // 2. Transfer Size per Beat (AWSIZE: 1B, 2B, 4B)
        // AXI4 Section A3.4.1: Transfer size shall not exceed the data bus width (32-bit = 4B).
        cp_awsize: coverpoint txn.size {
            bins size_1B = {3'b000};          // 1 Byte  (8-bit narrow transfer)
            bins size_2B = {3'b001};          // 2 Bytes (16-bit narrow transfer)
            bins size_4B = {3'b010};          // 4 Bytes (32-bit full bus width)
            illegal_bins size_exceeds_bus_width = {3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
        }

        // 3. Write Burst Type (AWBURST: FIXED, INCR, WRAP)
        cp_awburst: coverpoint txn.burst {
            bins burst_fixed  = {2'b00};      // FIXED
            bins burst_incr   = {2'b01};      // INCR
            bins burst_wrap   = {2'b10};      // WRAP
            illegal_bins rsvd = {2'b11};      // Reserved
        }

        // 4. Address Alignment (Lower 2 bits: awaddr[1:0])
        cp_awaddr_align: coverpoint (txn.addr[1:0]) {
            bins aligned_word = {2'b00};      // Word aligned (address multiple of 4)
            bins unaligned_01 = {2'b01};      // Offset by +1 byte
            bins unaligned_10 = {2'b10};      // Offset by +2 bytes (half-word)
            bins unaligned_11 = {2'b11};      // Offset by +3 bytes
        }

        // 5. Memory Address Range (0x0000 to 0xFFFF)
        cp_awaddr_range: coverpoint txn.addr {
            bins low_mem  = {[16'h0000 : 16'h0FFF]}; // Lower 4 KB
            bins mid_mem  = {[16'h1000 : 16'hEFFF]}; // General RAM memory
            bins high_mem = {[16'hF000 : 16'hFFFF]}; // Upper boundary
        }

        // 6. Write Transaction ID Tags (AWID)
        cp_awid: coverpoint txn.id {
            bins id_zero = {0};
            bins id_low  = {[1:15]};
            bins id_mid  = {[16:239]};
            bins id_high = {[240:255]};
        }

        // 7. Write Response Status (BRESP)
        cp_bresp: coverpoint txn.bresp {
            bins okay   = {2'b00};            // Normal access OKAY
            ignore_bins unsupported = {2'b01, 2'b10, 2'b11}; // Hardwired OKAY in RTL
        }

        // 8. Cross Coverage
        cross_awlen_awsize:  cross cp_awlen, cp_awsize;

        cross_awlen_awburst: cross cp_awlen, cp_awburst {
            // PROTOCOL EXCLUSION JUSTIFICATION (ARM AMBA AXI4 Spec Section A3.4.1):
            // 1. FIXED Bursts: Support for all other burst types remains at 1-16 transfers.
            //    Lengths > 16 beats are ILLEGAL in AXI4.
            ignore_bins fixed_unsupported_len = binsof(cp_awburst.burst_fixed) &&
                                                (binsof(cp_awlen.med_burst)  ||
                                                 binsof(cp_awlen.long_burst) ||
                                                 binsof(cp_awlen.max_burst));

            // 2. WRAP Bursts: Burst length must be 2, 4, 8, or 16 transfers.
            //    Single beat, other_short (3, 5..15), and >16 beats are ILLEGAL in WRAP mode.
            ignore_bins wrap_unsupported_len  = binsof(cp_awburst.burst_wrap) &&
                                                (binsof(cp_awlen.single_beat) ||
                                                 binsof(cp_awlen.other_short) ||
                                                 binsof(cp_awlen.med_burst)   ||
                                                 binsof(cp_awlen.long_burst)  ||
                                                 binsof(cp_awlen.max_burst));
        }

        cross_awlen_awalign: cross cp_awlen, cp_awaddr_align;

        // 3-way WRAP alignment legality cross (ARM AXI4 Spec Section A3.4.2)
        // For wrapping bursts, the start address must be aligned to the transfer size.
        cross_awburst_awsize_awalign: cross cp_awburst, cp_awsize, cp_awaddr_align {
            // size=4B WRAP: start address must be word-aligned (addr[1:0] == 2'b00)
            ignore_bins wrap_4B_unaligned = binsof(cp_awburst.burst_wrap) &&
                                            binsof(cp_awsize.size_4B) &&
                                            (binsof(cp_awaddr_align.unaligned_01) ||
                                             binsof(cp_awaddr_align.unaligned_10) ||
                                             binsof(cp_awaddr_align.unaligned_11));

            // size=2B WRAP: start address must be halfword-aligned (addr[0] == 1'b0)
            ignore_bins wrap_2B_unaligned = binsof(cp_awburst.burst_wrap) &&
                                            binsof(cp_awsize.size_2B) &&
                                            (binsof(cp_awaddr_align.unaligned_01) ||
                                             binsof(cp_awaddr_align.unaligned_11));
        }

    endgroup : cg_axi_write_xact

    // =========================================================================
    // Covergroup: PER-BEAT Write Attributes (W Channel)
    // Sampled for EVERY accepted beat (WVALID && WREADY) in the write burst.
    // =========================================================================
    covergroup cg_axi_write_beat;
        option.per_instance = 1;
        option.name = "cg_axi_write_beat";

        cp_latched_awlen: coverpoint latched_awlen {
            bins single_beat = {0};
            bins len_2       = {1};
            bins len_4       = {3};
            bins len_8       = {7};
            bins len_16      = {15};
            bins other_short = {[2], [4:6], [8:14]};
            bins med_burst   = {[16:63]};
            bins long_burst  = {[64:254]};
            bins max_burst   = {255};
        }

        cp_latched_awsize: coverpoint latched_awsize {
            bins size_1B = {3'b000};
            bins size_2B = {3'b001};
            bins size_4B = {3'b010};
            illegal_bins size_exceeds_bus_width = {3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
        }

        cp_wstrb: coverpoint current_strb {
            bins full_word        = {4'b1111};
            bins three_bytes      = {4'b0111, 4'b1110, 4'b1101, 4'b1011};
            bins two_bytes        = {4'b0011, 4'b1100, 4'b0110, 4'b1001, 4'b0101, 4'b1010};
            bins single_bytes     = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
            illegal_bins no_write = {4'b0000};
        }

        // Correlate burst length with per-beat byte strobe pattern
        cross_latched_awlen_wstrb: cross cp_latched_awlen, cp_wstrb;

        // Correlate transfer size with per-beat byte strobe (AXI4 Section A3.4.4)
        cross_latched_awsize_wstrb: cross cp_latched_awsize, cp_wstrb {
            // size_1B: only single active byte lane is legal
            ignore_bins size1B_illegal_strobe = binsof(cp_latched_awsize.size_1B) &&
                                                (binsof(cp_wstrb.two_bytes)   ||
                                                 binsof(cp_wstrb.three_bytes) ||
                                                 binsof(cp_wstrb.full_word));

            // size_2B: only aligned halfword patterns (0011 or 1100) are legal
            ignore_bins size2B_illegal_strobe = binsof(cp_latched_awsize.size_2B) &&
                                                (binsof(cp_wstrb.single_bytes) ||
                                                 binsof(cp_wstrb.three_bytes)  ||
                                                 binsof(cp_wstrb.full_word));

            ignore_bins size2B_unaligned_two_bytes = binsof(cp_latched_awsize.size_2B) &&
                                                     (binsof(cp_wstrb.two_bytes) intersect {4'b0110, 4'b1001, 4'b0101, 4'b1010});
        }

    endgroup : cg_axi_write_beat

    // =========================================================================
    // Covergroup for Read Channels (AR, R)
    // Sampled ONCE per completed read burst transaction.
    // =========================================================================
    covergroup cg_axi_read;
        option.per_instance = 1;
        option.name         = "cg_axi_read";

        // 1. Read Burst Length (ARLEN: 0 to 255 beats)
        cp_arlen: coverpoint txn.len {
            bins single_beat = {0};                  // 1 beat transfer (ARLEN=0)
            bins len_2       = {1};                  // 2 beats  (ARLEN=1,  valid for WRAP/INCR/FIXED)
            bins len_4       = {3};                  // 4 beats  (ARLEN=3,  valid for WRAP/INCR/FIXED)
            bins len_8       = {7};                  // 8 beats  (ARLEN=7,  valid for WRAP/INCR/FIXED)
            bins len_16      = {15};                 // 16 beats (ARLEN=15, valid for WRAP/INCR/FIXED)
            bins other_short = {[2], [4:6], [8:14]}; // 3, 5..7, 9..15 beats (INCR & FIXED only, illegal for WRAP)
            bins med_burst   = {[16:63]};            // 17 to 64 beats (INCR only, illegal for FIXED & WRAP)
            bins long_burst  = {[64:254]};           // 65 to 255 beats (INCR only, illegal for FIXED & WRAP)
            bins max_burst   = {255};                // 256 beats (AXI4 max limit, INCR only)
        }

        // 2. Read Transfer Size per Beat (ARSIZE: 1B, 2B, 4B)
        cp_arsize: coverpoint txn.size {
            bins size_1B = {3'b000};          // 1 Byte  (8-bit narrow transfer)
            bins size_2B = {3'b001};          // 2 Bytes (16-bit narrow transfer)
            bins size_4B = {3'b010};          // 4 Bytes (32-bit full bus width)
            illegal_bins size_exceeds_bus_width = {3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
        }

        // 3. Read Burst Type (ARBURST: FIXED, INCR, WRAP)
        cp_arburst: coverpoint txn.burst {
            bins burst_fixed  = {2'b00};      // FIXED
            bins burst_incr   = {2'b01};      // INCR
            bins burst_wrap   = {2'b10};      // WRAP
            illegal_bins rsvd = {2'b11};      // Reserved
        }

        // 4. Read Address Alignment (Lower 2 bits: araddr[1:0])
        cp_araddr_align: coverpoint (txn.addr[1:0]) {
            bins aligned_word = {2'b00};      // Word aligned
            bins unaligned_01 = {2'b01};      // Offset by +1 byte
            bins unaligned_10 = {2'b10};      // Offset by +2 bytes (half-word)
            bins unaligned_11 = {2'b11};      // Offset by +3 bytes
        }

        // 5. Read Memory Address Range (0x0000 to 0xFFFF)
        cp_araddr_range: coverpoint txn.addr {
            bins low_mem  = {[16'h0000 : 16'h0FFF]}; // Lower 4 KB
            bins mid_mem  = {[16'h1000 : 16'hEFFF]}; // General RAM memory
            bins high_mem = {[16'hF000 : 16'hFFFF]}; // Upper boundary
        }

        // 6. Read Transaction ID Tags (ARID)
        cp_arid: coverpoint txn.id {
            bins id_zero = {0};
            bins id_low  = {[1:15]};
            bins id_mid  = {[16:239]};
            bins id_high = {[240:255]};
        }

        // 7. Read Response Status (RRESP beat 0)
        cp_rresp: coverpoint txn.rresp[0] {
            bins okay   = {2'b00};            // Normal access OKAY
            ignore_bins unsupported = {2'b01, 2'b10, 2'b11};
        }

        // 8. Cross Coverage
        cross_arlen_arsize:   cross cp_arlen, cp_arsize;

        cross_arlen_arburst:  cross cp_arlen, cp_arburst {
            ignore_bins fixed_unsupported_len = binsof(cp_arburst.burst_fixed) &&
                                                (binsof(cp_arlen.med_burst)  ||
                                                 binsof(cp_arlen.long_burst) ||
                                                 binsof(cp_arlen.max_burst));

            ignore_bins wrap_unsupported_len  = binsof(cp_arburst.burst_wrap) &&
                                                (binsof(cp_arlen.single_beat) ||
                                                 binsof(cp_arlen.other_short) ||
                                                 binsof(cp_arlen.med_burst)   ||
                                                 binsof(cp_arlen.long_burst)  ||
                                                 binsof(cp_arlen.max_burst));
        }

        cross_arsize_arburst: cross cp_arsize, cp_arburst;
        cross_arlen_aralign:  cross cp_arlen, cp_araddr_align;

        // 3-way WRAP alignment legality cross (ARM AXI4 Spec Section A3.4.2)
        cross_arburst_arsize_aralign: cross cp_arburst, cp_arsize, cp_araddr_align {
            // size=4B WRAP: start address must be word-aligned (addr[1:0] == 2'b00)
            ignore_bins wrap_4B_unaligned = binsof(cp_arburst.burst_wrap) &&
                                            binsof(cp_arsize.size_4B) &&
                                            (binsof(cp_araddr_align.unaligned_01) ||
                                             binsof(cp_araddr_align.unaligned_10) ||
                                             binsof(cp_araddr_align.unaligned_11));

            // size=2B WRAP: start address must be halfword-aligned (addr[0] == 1'b0)
            ignore_bins wrap_2B_unaligned = binsof(cp_arburst.burst_wrap) &&
                                            binsof(cp_arsize.size_2B) &&
                                            (binsof(cp_araddr_align.unaligned_01) ||
                                             binsof(cp_araddr_align.unaligned_11));
        }

    endgroup : cg_axi_read

    function new(string name = "axi_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_axi_write_xact = new();
        cg_axi_write_beat = new();
        cg_axi_read       = new();
    endfunction : new

    // Subscriber write implementation: samples appropriate covergroup based on transaction type
    virtual function void write(item_type t);
        this.txn = t;
        if (txn.trans_type == AXI_WRITE) begin
            latched_awlen  = txn.len;
            latched_awsize = txn.size;

            // 1. Sample transaction-level covergroup ONCE per write burst
            cg_axi_write_xact.sample();

            // 2. Sample beat-level covergroup for EVERY beat in the write burst
            foreach (txn.strb[i]) begin
                current_strb = txn.strb[i];
                cg_axi_write_beat.sample();
            end
        end else begin
            // Sample read covergroup ONCE per read burst
            cg_axi_read.sample();
        end
    endfunction : write

endclass : axi_coverage

`endif // AXI_COVERAGE_SV
