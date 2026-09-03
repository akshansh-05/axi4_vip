// File: axi_seq_item.sv
// Sequence item modeling AXI4 memory-mapped burst transactions across AW, W, B, AR, and R channels.

`ifndef AXI_SEQ_ITEM_SV
`define AXI_SEQ_ITEM_SV

// Transaction direction
typedef enum bit {
    AXI_READ  = 1'b0,
    AXI_WRITE = 1'b1
} axi_trans_type_e;

// Burst types defined by ARM AXI4 specification
typedef enum bit [1:0] {
    AXI_BURST_FIXED = 2'b00,  // Address remains fixed (e.g. FIFO accesses)
    AXI_BURST_INCR  = 2'b01,  // Address increments each beat (sequential memory)
    AXI_BURST_WRAP  = 2'b10,  // Address wraps at cacheline boundary
    AXI_BURST_RSVD  = 2'b11   // Reserved
} axi_burst_type_e;

// Response status codes
typedef enum bit [1:0] {
    AXI_RESP_OKAY   = 2'b00,  // Normal access success
    AXI_RESP_EXOKAY = 2'b01,  // Exclusive access success
    AXI_RESP_SLVERR = 2'b10,  // Slave error (access fault)
    AXI_RESP_DECERR = 2'b11   // Decode error (invalid address)
} axi_resp_e;

class axi_seq_item #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_sequence_item;

    // Transaction request attributes
    rand axi_trans_type_e         trans_type;  // READ or WRITE
    rand bit [ID_WIDTH-1:0]       id;          // AWID or ARID
    rand bit [ADDR_WIDTH-1:0]     addr;        // Burst starting address
    rand bit [7:0]                len;         // Burst length: 0 to 255 (representing 1 to 256 beats)
    rand bit [2:0]                size;        // Transfer size per beat: 0=1B, 1=2B, 2=4B, etc.
    rand axi_burst_type_e         burst;       // FIXED, INCR, or WRAP

    // Dynamic arrays sized to (len + 1)
    rand bit [DATA_WIDTH-1:0]     data[];      // Payload data words
    rand bit [STRB_WIDTH-1:0]     strb[];      // Byte strobes for write beats

    // Optional delay controls for random bus throttling
    rand int unsigned             addr_delay;  // Delay before driving address valid
    rand int unsigned             data_delay[];// Delay before driving write data valid

    // Response attributes captured from the slave
    bit [ID_WIDTH-1:0]            bid;         // Write response ID
    bit [1:0]                     bresp;       // Write response status
    bit [ID_WIDTH-1:0]            rid[];       // Read response ID per beat
    bit [1:0]                     rresp[];     // Read response status per beat

    // UVM Field Macros for automatic print(), copy(), compare(), and record()
    `uvm_object_param_utils_begin(axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))
        `uvm_field_enum     (axi_trans_type_e, trans_type, UVM_ALL_ON)
        `uvm_field_int      (id,                           UVM_ALL_ON)
        `uvm_field_int      (addr,                         UVM_ALL_ON | UVM_HEX)
        `uvm_field_int      (len,                          UVM_ALL_ON | UVM_DEC)
        `uvm_field_int      (size,                         UVM_ALL_ON | UVM_DEC)
        `uvm_field_enum     (axi_burst_type_e, burst,      UVM_ALL_ON)
        `uvm_field_array_int(data,                         UVM_ALL_ON | UVM_HEX)
        `uvm_field_array_int(strb,                         UVM_ALL_ON | UVM_BIN)
        `uvm_field_int      (addr_delay,                   UVM_ALL_ON | UVM_DEC)
        `uvm_field_array_int(data_delay,                   UVM_ALL_ON | UVM_DEC)
        `uvm_field_int      (bid,                          UVM_ALL_ON)
        `uvm_field_int      (bresp,                        UVM_ALL_ON | UVM_BIN)
        `uvm_field_array_int(rid,                          UVM_ALL_ON)
        `uvm_field_array_int(rresp,                        UVM_ALL_ON | UVM_BIN)
    `uvm_object_utils_end

    // Sizing constraints: arrays must match burst beat count
    constraint c_array_sizes {
        data.size()       == (len + 1);
        strb.size()       == (len + 1);
        data_delay.size() == (len + 1);
    }

    // Beat size cannot exceed the physical bus width
    constraint c_size_limit {
        size == $clog2(STRB_WIDTH); // size = 4 bytes 
    }

    // AXI 4KB boundary constraint: INCR bursts must not cross a 4KB boundary
    constraint c_4kb_boundary {
        if (burst == AXI_BURST_INCR) {
            (addr % 4096) + ((len + 1) * (1 << size)) <= 4096;
        }
    }

    // WRAP burst constraints: length must be 2, 4, 8, or 16 and address aligned
    constraint c_wrap_rules {
        if (burst == AXI_BURST_WRAP) {
            len inside {8'd1, 8'd3, 8'd7, 8'd15};
            addr % (1 << size) == 0;
        }
    }

    // Default distributions for verification
    constraint c_default_burst_distribution {
        soft len inside {[8'd0 : 8'd15]};
        soft addr_delay inside {[0 : 3]};
        foreach (data_delay[i]) {
            soft data_delay[i] inside {[0 : 3]};
        }
        foreach (strb[i]) {
            soft strb[i] == {STRB_WIDTH{1'b1}};
        }
    }

    function new(string name = "axi_seq_item");
        super.new(name);
    endfunction : new

endclass : axi_seq_item

`endif // AXI_SEQ_ITEM_SV
