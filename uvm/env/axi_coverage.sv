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

    // Transaction handle and per-beat strobe holder used for sampling covergroups
    item_type            txn;
    bit [STRB_WIDTH-1:0] current_strb;

    // Covergroup for Write Channels (AW, W, B)
    covergroup cg_axi_write;
        option.per_instance = 1;
        option.name = "cg_axi_write";

        // 1. Write Burst Length (AWLEN: 0 to 255 beats)
        cp_awlen: coverpoint txn.len {
            bins single_beat = {0};           // 1 beat transfer
            bins short_burst = {[1:15]};      // 2 to 16 beats
            bins med_burst   = {[16:63]};     // 17 to 64 beats
            bins long_burst  = {[64:254]};    // 65 to 255 beats
            bins max_burst   = {255};         // 256 beats (AXI4 max limit)
        }

        // 2. Transfer Size per Beat (AWSIZE: 1B, 2B, 4B)
        cp_awsize: coverpoint txn.size {
            bins size_1B = {3'b000};          // 1 Byte  (8-bit narrow transfer)
            bins size_2B = {3'b001};          // 2 Bytes (16-bit narrow transfer)
            bins size_4B = {3'b010};          // 4 Bytes (32-bit full bus width)
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

        // 6. Write Byte Strobes (WSTRB sampled for every beat in the burst)
        cp_wstrb: coverpoint current_strb {
            bins full_word        = {4'b1111};
            bins three_bytes      = {4'b0111, 4'b1110, 4'b1101, 4'b1011};
            bins two_bytes        = {4'b0011, 4'b1100, 4'b0110, 4'b1001, 4'b0101, 4'b1010};
            bins single_bytes     = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
            illegal_bins no_write = {4'b0000};
        }

        // 7. Write Transaction ID Tags (AWID)
        cp_awid: coverpoint txn.id {
            bins id_zero = {0};
            bins id_low  = {[1:15]};
            bins id_mid  = {[16:239]};
            bins id_high = {[240:255]};
        }

        // 8. Write Response Status (BRESP)
        cp_bresp: coverpoint txn.bresp {
            bins okay   = {2'b00};            // Normal access OKAY
            ignore_bins unsupported = {2'b01,2'b10,2'b11};
        }

        // 9. Cross Coverage
        cross_awlen_awsize:   cross cp_awlen, cp_awsize;
        cross_awlen_awburst:  cross cp_awlen, cp_awburst;
        cross_awlen_wstrb:    cross cp_awlen, cp_wstrb;
        cross_awlen_awalign:  cross cp_awlen, cp_awaddr_align;
    endgroup : cg_axi_write

    // Covergroup for Read Channels (AR, R)
    covergroup cg_axi_read;
        option.per_instance = 1;
        option.name         = "cg_axi_read";

        // 1. Read Burst Length (ARLEN: 0 to 255 beats)
        cp_arlen: coverpoint txn.len {
            bins single_beat = {0};           // 1 beat transfer
            bins short_burst = {[1:15]};      // 2 to 16 beats
            bins med_burst   = {[16:63]};     // 17 to 64 beats
            bins long_burst  = {[64:254]};    // 65 to 255 beats
            bins max_burst   = {255};         // 256 beats (AXI4 max limit)
        }

        // 2. Read Transfer Size per Beat (ARSIZE: 1B, 2B, 4B)
        cp_arsize: coverpoint txn.size {
            bins size_1B = {3'b000};          // 1 Byte  (8-bit narrow transfer)
            bins size_2B = {3'b001};          // 2 Bytes (16-bit narrow transfer)
            bins size_4B = {3'b010};          // 4 Bytes (32-bit full bus width)
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
            ignore_bins unsupported = {2'b01,2'b10,2'b11};
        }

        // 8. Cross Coverage
        cross_arlen_arsize:   cross cp_arlen, cp_arsize;
        cross_arlen_arburst:  cross cp_arlen, cp_arburst;
        cross_arsize_arburst: cross cp_arsize, cp_arburst;
        cross_arlen_aralign:  cross cp_arlen, cp_araddr_align;
    endgroup : cg_axi_read

    function new(string name = "axi_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_axi_write = new();
        cg_axi_read  = new();
    endfunction : new

    // Subscriber write implementation: samples appropriate covergroup based on transaction type
    virtual function void write(item_type t);
        this.txn = t;
        if (txn.trans_type == AXI_WRITE) begin
            // Samples strobe for EVERY beat in the write burst
            foreach (txn.strb[i]) begin
                current_strb = txn.strb[i];
                cg_axi_write.sample();
            end
        end else begin
            cg_axi_read.sample();
        end
    endfunction : write

endclass : axi_coverage

`endif // AXI_COVERAGE_SV
