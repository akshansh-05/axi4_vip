// File: tb_params_pkg.sv
// Global Testbench Configuration and Parameter Package matching DUT hardware specs.

`ifndef TB_PARAMS_PKG_SV
`define TB_PARAMS_PKG_SV

package tb_params_pkg;

    // AXI4 Memory-Mapped & Stream Bus Parameters
    parameter int DATA_WIDTH        = 32;
    parameter int ADDR_WIDTH        = 16;
    parameter int ID_WIDTH          = 8;
    parameter int STRB_WIDTH        = (DATA_WIDTH / 8);
    parameter int MAX_BURST_LEN     = 16;

    // DMA Descriptor Parameters
    parameter int LEN_WIDTH         = 20;
    parameter int TAG_WIDTH         = 8;
    parameter int DEST_WIDTH        = 8;
    parameter int USER_WIDTH        = 1;
    parameter int PIPELINE_OUTPUT   = 0;

endpackage : tb_params_pkg

`endif // TB_PARAMS_PKG_SV
