// File: axis_if.sv
// AXI4-Stream Interface.

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

    logic [DATA_WIDTH-1:0]  tdata;
    logic [KEEP_WIDTH-1:0]  tkeep;
    logic                   tvalid;
    logic                   tready;
    logic                   tlast;
    logic [ID_WIDTH-1:0]    tid;
    logic [DEST_WIDTH-1:0]  tdest;
    logic [USER_WIDTH-1:0]  tuser;

    // Clocking Blocks
    // Write Driver Clocking Block (Master driving stream data into DUT)
    clocking wr_drv_cb @(posedge clk);
        default input #1step output #0;
        output tdata, tkeep, tvalid, tlast, tid, tdest, tuser;
        input  tready;
    endclocking : wr_drv_cb

    // Read Driver Clocking Block (Slave receiving stream data from DUT)
    clocking rd_drv_cb @(posedge clk);
        default input #1step output #0;
        output tready;
        input  tdata, tkeep, tvalid, tlast, tid, tdest, tuser;
    endclocking : rd_drv_cb

    // Monitor Clocking Block (Passive sampling of all stream signals)
    clocking mon_cb @(posedge clk);
        default input #1step output #0;
        input  tdata, tkeep, tvalid, tready, tlast, tid, tdest, tuser;
    endclocking : mon_cb

    // Modports
    modport wr_drv_mp (clocking wr_drv_cb, input clk, input rst);
    modport rd_drv_mp (clocking rd_drv_cb, input clk, input rst);
    modport mon_mp    (clocking mon_cb,    input clk, input rst);

endinterface : axis_if

`endif // AXIS_IF_SV

