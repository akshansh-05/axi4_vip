// File: axis_pkg.sv
// Description: Package bundling all AXI4-Stream VIP components.

`ifndef AXIS_PKG_SV
`define AXIS_PKG_SV

package axis_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "axis_seq_item.sv"
    `include "axis_agent_config.sv"
    `include "axis_sequencer.sv"
    `include "axis_wr_driver.sv"
    `include "axis_wr_monitor.sv"
    `include "axis_wr_agent.sv"
    `include "axis_rd_driver.sv"
    `include "axis_rd_monitor.sv"
    `include "axis_rd_agent.sv"

    // Sequence library
    `include "sequences/axis_base_seq.sv"
    `include "sequences/axis_packet_seq.sv"
    `include "sequences/axis_slave_rx_seq.sv"

endpackage : axis_pkg

`endif // AXIS_PKG_SV
