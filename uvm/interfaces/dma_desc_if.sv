// File: dma_desc_if.sv
// Description: Descriptor Command & Status Interface for AXI DMA Core
//              Includes dedicated Clocking Blocks and Modports for Read & Write Agents.

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

    // 1. Global Controls
    logic                   read_enable;
    logic                   write_enable;
    logic                   write_abort;

    // 2. Read Descriptor Command Channel
    logic [ADDR_WIDTH-1:0]  read_desc_addr;
    logic [LEN_WIDTH-1:0]   read_desc_len;
    logic [TAG_WIDTH-1:0]   read_desc_tag;
    logic [ID_WIDTH-1:0]    read_desc_id;
    logic [DEST_WIDTH-1:0]  read_desc_dest;
    logic [USER_WIDTH-1:0]  read_desc_user;
    logic                   read_desc_valid;
    logic                   read_desc_ready;

    // 3. Read Descriptor Status Channel
    logic [TAG_WIDTH-1:0]   read_desc_status_tag;
    logic [3:0]             read_desc_status_error;     // DMA_ERROR codes (0=None, 4=SLVERR, 5=DECERR)
    logic                   read_desc_status_valid;

    // 4. Write Descriptor Command Channel
    logic [ADDR_WIDTH-1:0]  write_desc_addr;
    logic [LEN_WIDTH-1:0]   write_desc_len;
    logic [TAG_WIDTH-1:0]   write_desc_tag;
    logic                   write_desc_valid;
    logic                   write_desc_ready;

    // 5. Write Descriptor Status Channel
    logic [LEN_WIDTH-1:0]   write_desc_status_len;      // Actual byte length written
    logic [TAG_WIDTH-1:0]   write_desc_status_tag;
    logic [ID_WIDTH-1:0]    write_desc_status_id;
    logic [DEST_WIDTH-1:0]  write_desc_status_dest;
    logic [USER_WIDTH-1:0]  write_desc_status_user;
    logic [3:0]             write_desc_status_error;    // DMA_ERROR codes (0=None, 6=SLVERR, 7=DECERR)
    logic                   write_desc_status_valid;

    // 6. Clocking Blocks

    // Read Descriptor Driver Clocking Block
    clocking rd_desc_drv_cb @(posedge clk);
        default input #1step output #0;
        output read_enable;
        output read_desc_addr, read_desc_len, read_desc_tag, read_desc_id, read_desc_dest, read_desc_user, read_desc_valid;
        input  read_desc_ready;
        input  read_desc_status_tag, read_desc_status_error, read_desc_status_valid;
    endclocking : rd_desc_drv_cb

    // Write Descriptor Driver Clocking Block
    clocking wr_desc_drv_cb @(posedge clk);
        default input #1step output #0;
        output write_enable, write_abort;
        output write_desc_addr, write_desc_len, write_desc_tag, write_desc_valid;
        input  write_desc_ready;
        input  write_desc_status_len, write_desc_status_tag, write_desc_status_id, write_desc_status_dest, write_desc_status_user, write_desc_status_error, write_desc_status_valid;
    endclocking : wr_desc_drv_cb

    // Read Descriptor Monitor Clocking Block (Sample only)
    clocking rd_desc_mon_cb @(posedge clk);
        default input #1step output #0;
        input  read_enable;
        input  read_desc_addr, read_desc_len, read_desc_tag, read_desc_id, read_desc_dest, read_desc_user, read_desc_valid, read_desc_ready;
        input  read_desc_status_tag, read_desc_status_error, read_desc_status_valid;
    endclocking : rd_desc_mon_cb

    // Write Descriptor Monitor Clocking Block (Sample only)
    clocking wr_desc_mon_cb @(posedge clk);
        default input #1step output #0;
        input  write_enable, write_abort;
        input  write_desc_addr, write_desc_len, write_desc_tag, write_desc_valid, write_desc_ready;
        input  write_desc_status_len, write_desc_status_tag, write_desc_status_id, write_desc_status_dest, write_desc_status_user, write_desc_status_error, write_desc_status_valid;
    endclocking : wr_desc_mon_cb

    // 7. Modports
    
    modport rd_drv_mp (clocking rd_desc_drv_cb, input clk, input rst);
    modport wr_drv_mp (clocking wr_desc_drv_cb, input clk, input rst);
    modport rd_mon_mp (clocking rd_desc_mon_cb, input clk, input rst);
    modport wr_mon_mp (clocking wr_desc_mon_cb, input clk, input rst);

endinterface : dma_desc_if

`endif // DMA_DESC_IF_SV
