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

endinterface : axis_if

`endif // AXIS_IF_SV
