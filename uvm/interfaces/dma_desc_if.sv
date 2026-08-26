// File: dma_desc_if.sv
// DMA Descriptor Command and Status Interface.

`ifndef DMA_DESC_IF_SV
`define DMA_DESC_IF_SV

interface dma_desc_if #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
)(
    input logic clk,
    input logic rst
);

    // Read Descriptor Command
    logic [ADDR_WIDTH-1:0]  read_desc_addr;
    logic [LEN_WIDTH-1:0]   read_desc_len;
    logic [TAG_WIDTH-1:0]   read_desc_tag;
    logic [ID_WIDTH-1:0]    read_desc_id;
    logic [DEST_WIDTH-1:0]  read_desc_dest;
    logic [USER_WIDTH-1:0]  read_desc_user;
    logic                   read_desc_valid;
    logic                   read_desc_ready;

    // Read Descriptor Status
    logic [TAG_WIDTH-1:0]   read_desc_status_tag;
    logic [3:0]             read_desc_status_error;
    logic                   read_desc_status_valid;

    // Write Descriptor Command
    logic [ADDR_WIDTH-1:0]  write_desc_addr;
    logic [LEN_WIDTH-1:0]   write_desc_len;
    logic [TAG_WIDTH-1:0]   write_desc_tag;
    logic                   write_desc_valid;
    logic                   write_desc_ready;

    // Write Descriptor Status
    logic [LEN_WIDTH-1:0]   write_desc_status_len;
    logic [TAG_WIDTH-1:0]   write_desc_status_tag;
    logic [ID_WIDTH-1:0]    write_desc_status_id;
    logic [DEST_WIDTH-1:0]  write_desc_status_dest;
    logic [USER_WIDTH-1:0]  write_desc_status_user;
    logic [3:0]             write_desc_status_error;
    logic                   write_desc_status_valid;

    // Controls
    logic                   read_enable;
    logic                   write_enable;
    logic                   write_abort;

endinterface : dma_desc_if

`endif // DMA_DESC_IF_SV
