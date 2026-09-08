// File: axi_if.sv
// AXI4 Memory-Mapped bus interface with IEEE 1800 Standard Clocking Blocks.

`ifndef AXI_IF_SV
`define AXI_IF_SV

interface axi_if #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
)(
    input logic clk,
    input logic rst
);

    // 1. Physical Bus Nets (wire nets allow bidirectional driver & DUT connections)

    // Write Address Channel (AW)
    wire [ID_WIDTH-1:0]    awid;
    wire [ADDR_WIDTH-1:0]  awaddr;
    wire [7:0]             awlen;
    wire [2:0]             awsize;
    wire [1:0]             awburst;
    wire                   awvalid;
    wire                   awready;

    // Write Data Channel (W)
    wire [DATA_WIDTH-1:0]  wdata;
    wire [STRB_WIDTH-1:0]  wstrb;
    wire                   wlast;
    wire                   wvalid;
    wire                   wready;

    // Write Response Channel (B)
    wire [ID_WIDTH-1:0]    bid;
    wire [1:0]             bresp;
    wire                   bvalid;
    wire                   bready;

    // Read Address Channel (AR)
    wire [ID_WIDTH-1:0]    arid;
    wire [ADDR_WIDTH-1:0]  araddr;
    wire [7:0]             arlen;
    wire [2:0]             arsize;
    wire [1:0]             arburst;
    wire                   arvalid;
    wire                   arready;

    // Read Data Channel (R)
    wire [ID_WIDTH-1:0]    rid;
    wire [DATA_WIDTH-1:0]  rdata;
    wire [1:0]             rresp;
    wire                   rlast;
    wire                   rvalid;
    wire                   rready;

    // 2. Clocking Blocks (input #1step samples Preponed; output #0 drives immediately after clock edge)

    // 2A. Master Driver Clocking Blocks (For driving Slave DUT e.g. axi_ram)
    // Master Write Driver Clocking Block (AW, W, B Channels)
    clocking wr_drv_cb @(posedge clk);
        default input #1step output #0;
        output awid, awaddr, awlen, awsize, awburst, awvalid;
        input  awready;
        output wdata, wstrb, wlast, wvalid;
        input  wready;
        input  bid, bresp, bvalid;
        output bready;
    endclocking : wr_drv_cb

    // Master Read Driver Clocking Block (AR, R Channels)
    clocking rd_drv_cb @(posedge clk);
        default input #1step output #0;
        output arid, araddr, arlen, arsize, arburst, arvalid;
        input  arready;
        input  rid, rdata, rresp, rlast, rvalid;
        output rready;
    endclocking : rd_drv_cb

    // 2B. Slave Driver Clocking Blocks (For responding to Master DUT e.g. axi_dma)
    // Slave Write Driver Clocking Block (Responds to AW, W; generates B)
    clocking wr_slv_drv_cb @(posedge clk);
        default input #1step output #0;
        input  awid, awaddr, awlen, awsize, awburst, awvalid;
        output awready;
        input  wdata, wstrb, wlast, wvalid;
        output wready;
        output bid, bresp, bvalid;
        input  bready;
    endclocking : wr_slv_drv_cb

    // Slave Read Driver Clocking Block (Responds to AR; generates R)
    clocking rd_slv_drv_cb @(posedge clk);
        default input #1step output #0;
        input  arid, araddr, arlen, arsize, arburst, arvalid;
        output arready;
        output rid, rdata, rresp, rlast, rvalid;
        input  rready;
    endclocking : rd_slv_drv_cb

    // 2C. Monitor Clocking Blocks (Sample-only for passive snooping)
    clocking wr_mon_cb @(posedge clk);
        default input #1step output #0;
        input awid, awaddr, awlen, awsize, awburst, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
    endclocking : wr_mon_cb

    clocking rd_mon_cb @(posedge clk);
        default input #1step output #0;
        input arid, araddr, arlen, arsize, arburst, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking : rd_mon_cb

    // 3. Modports
    modport wr_drv_mp     (clocking wr_drv_cb,     input clk, input rst);
    modport rd_drv_mp     (clocking rd_drv_cb,     input clk, input rst);
    modport wr_slv_drv_mp (clocking wr_slv_drv_cb, input clk, input rst);
    modport rd_slv_drv_mp (clocking rd_slv_drv_cb, input clk, input rst);
    modport wr_mon_mp     (clocking wr_mon_cb,     input clk, input rst);
    modport rd_mon_mp     (clocking rd_mon_cb,     input clk, input rst);

endinterface : axi_if

`endif // AXI_IF_SV
