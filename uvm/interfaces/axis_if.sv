// File: axis_if.sv
// AXI4-Stream Interface with IEEE 1800 Standard Clocking Blocks.

`ifndef AXIS_IF_SV
`define AXIS_IF_SV

interface axis_if #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
)(
    input logic clk,
    input logic rst
);

    // Physical Bus Nets
    logic [DATA_WIDTH-1:0]  tdata;
    logic [KEEP_WIDTH-1:0]  tkeep;
    logic                   tvalid;
    logic                   tready;
    logic                   tlast;
    logic [ID_WIDTH-1:0]    tid;
    logic [DEST_WIDTH-1:0]  tdest;
    logic [USER_WIDTH-1:0]  tuser;

    // Clocking Blocks (input #1step samples Preponed; output #0 drives immediately after clock edge)

    // Master Driver CB (Producer: drives TDATA/TVALID/TLAST, samples TREADY from DUT)
    clocking mst_drv_cb @(posedge clk);
        default input #1step output #0;
        output tdata, tkeep, tvalid, tlast, tid, tdest, tuser;
        input  tready;
    endclocking : mst_drv_cb

    // Slave Driver CB (Consumer: drives TREADY, samples TVALID/TDATA from DUT)
    clocking slv_drv_cb @(posedge clk);
        default input #1step output #0;
        input  tdata, tkeep, tvalid, tlast, tid, tdest, tuser;
        output tready;
    endclocking : slv_drv_cb

    // Write Driver Clocking Block alias (Master driving stream data into DUT)
    clocking wr_drv_cb @(posedge clk);
        default input #1step output #0;
        output tdata, tkeep, tvalid, tlast, tid, tdest, tuser;
        input  tready;
    endclocking : wr_drv_cb

    // Read Driver Clocking Block alias (Slave receiving stream data from DUT)
    clocking rd_drv_cb @(posedge clk);
        default input #1step output #0;
        output tready;
        input  tdata, tkeep, tvalid, tlast, tid, tdest, tuser;
    endclocking : rd_drv_cb

    // Monitor CB (Passive: sample-only for all signals)
    clocking mon_cb @(posedge clk);
        default input #1step output #0;
        input  tdata, tkeep, tvalid, tready, tlast, tid, tdest, tuser;
    endclocking : mon_cb

    // Modports
    modport mst_drv_mp (clocking mst_drv_cb, input clk, input rst);
    modport slv_drv_mp (clocking slv_drv_cb, input clk, input rst);
    modport wr_drv_mp  (clocking wr_drv_cb,  input clk, input rst);
    modport rd_drv_mp  (clocking rd_drv_cb,  input clk, input rst);
    modport mon_mp     (clocking mon_cb,     input clk, input rst);

endinterface : axis_if

`endif // AXIS_IF_SV

