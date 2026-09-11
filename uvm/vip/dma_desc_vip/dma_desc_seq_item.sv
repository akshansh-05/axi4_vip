// File: dma_desc_seq_item.sv
// Description: Sequence item modeling DMA Read and Write descriptors
//              for the AXI4 DMA Subsystem. Covers both command issuance
//              and status response channels.

`ifndef DMA_DESC_SEQ_ITEM_SV
`define DMA_DESC_SEQ_ITEM_SV

// Descriptor direction / engine type
typedef enum bit {
    DESC_READ  = 1'b0, // Read Descriptor (MM2S: Memory-to-Stream)
    DESC_WRITE = 1'b1  // Write Descriptor (S2MM: Stream-to-Memory)
} dma_desc_type_e;

// DMA Status Error Codes (matches RTL specification)
typedef enum bit [3:0] {
    DMA_ERR_NONE          = 4'd0,  // Normal completion (OKAY)
    DMA_ERR_TIMEOUT       = 4'd1,  // Timeout waiting for channel handshake
    DMA_ERR_PARITY        = 4'd2,  // Internal parity error
    DMA_ERR_AXI_RD_SLVERR = 4'd4,  // AXI RRESP SLVERR during read
    DMA_ERR_AXI_RD_DECERR = 4'd5,  // AXI RRESP DECERR during read
    DMA_ERR_AXI_WR_SLVERR = 4'd6,  // AXI BRESP SLVERR during write
    DMA_ERR_AXI_WR_DECERR = 4'd7,  // AXI BRESP DECERR during write
    DMA_ERR_PCIE_FLR      = 4'd8   // Reserved / PCIE FLR
} dma_error_e;

class dma_desc_seq_item #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence_item;

    // 1. Command Fields (Driven to DUT)
    rand dma_desc_type_e         trans_type;   // DESC_READ or DESC_WRITE
    rand bit [ADDR_WIDTH-1:0]    addr;         // Source (Read) or Destination (Write) Address
    rand bit [LEN_WIDTH-1:0]     len;          // Byte length to transfer (or max write buffer)
    rand bit [TAG_WIDTH-1:0]     tag;          // Transaction Tag for matching status
    rand bit [ID_WIDTH-1:0]      id;           // Stream TID (read command)
    rand bit [DEST_WIDTH-1:0]    dest;         // Stream TDEST (read command)
    rand bit [USER_WIDTH-1:0]    user;         // Stream TUSER (read command)

    // Optional delay cycles before asserting valid
    rand int unsigned            valid_delay;

    // 2. Status Response Fields (Sampled from DUT upon transfer completion)

    bit [TAG_WIDTH-1:0]          status_tag;   // Tag matching the completed descriptor
    dma_error_e                  status_error; // Error status code (0 = None)
    bit [LEN_WIDTH-1:0]          status_len;   // Actual byte count written (Write DMA)
    bit [ID_WIDTH-1:0]           status_id;    // Stream TID captured at completion (Write DMA)
    bit [DEST_WIDTH-1:0]         status_dest;  // Stream TDEST captured at completion (Write DMA)
    bit [USER_WIDTH-1:0]         status_user;  // Stream TUSER captured at completion (Write DMA)

    // 3. UVM Field Macros

    `uvm_object_param_utils_begin(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))
        `uvm_field_enum (dma_desc_type_e, trans_type,   UVM_ALL_ON)
        `uvm_field_int  (addr,                          UVM_ALL_ON | UVM_HEX)
        `uvm_field_int  (len,                           UVM_ALL_ON | UVM_DEC)
        `uvm_field_int  (tag,                           UVM_ALL_ON | UVM_HEX)
        `uvm_field_int  (id,                            UVM_ALL_ON | UVM_HEX)
        `uvm_field_int  (dest,                          UVM_ALL_ON | UVM_HEX)
        `uvm_field_int  (user,                          UVM_ALL_ON | UVM_BIN)
        `uvm_field_int  (valid_delay,                   UVM_ALL_ON | UVM_DEC)
        `uvm_field_int  (status_tag,                    UVM_ALL_ON | UVM_HEX)
        `uvm_field_enum (dma_error_e,     status_error, UVM_ALL_ON)
        `uvm_field_int  (status_len,                    UVM_ALL_ON | UVM_DEC)
        `uvm_field_int  (status_id,                     UVM_ALL_ON | UVM_HEX)
        `uvm_field_int  (status_dest,                   UVM_ALL_ON | UVM_HEX)
        `uvm_field_int  (status_user,                   UVM_ALL_ON | UVM_BIN)
    `uvm_object_utils_end

    // 4. Constraints

    // Byte length must be strictly non-zero
    constraint c_len_positive {
        len > 0;
    }

    // Default transfer length distribution: biased toward fast transfers while covering multi-burst stress
    constraint c_default_len {
        soft len dist {
            [1    : 64]   :/ 50,  // Short transfers (1 to 2 AXI bursts) - 50%
            [65   : 512]  :/ 35,  // Medium transfers (multi-burst)      - 35%
            [513  : 4096] :/ 15   // Large stress transfers (up to 4KB)  - 15%
        };
    }

    // Ensure entire transfer fits within 64KB SRAM space without overflowing 0xFFFF
    constraint c_default_addr {
        soft addr <= (1 << ADDR_WIDTH) - 1 - len;
    }

    // Default to 4-byte word-aligned addresses for clean memory access
    constraint c_default_alignment {
        soft addr[1:0] == 2'b00;
    }

    // Default sideband signals to zero unless explicitly constrained
    constraint c_default_sideband {
        soft id   == '0;
        soft dest == '0;
        soft user == '0;
    }

    // Throttle / backpressure delay
    constraint c_default_delay {
        soft valid_delay inside {[0 : 3]};
    }

    // 5. Methods
    function new(string name = "dma_desc_seq_item");
        super.new(name);
    endfunction : new

endclass : dma_desc_seq_item

`endif // DMA_DESC_SEQ_ITEM_SV
