// File: axi_sequencer.sv
// AXI4 Sequencer specialized for AXI-MM items.

`ifndef AXI_SEQUENCER_SV
`define AXI_SEQUENCER_SV

class axi_sequencer #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_sequencer #(axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH));

    `uvm_component_param_utils(axi_sequencer #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

endclass : axi_sequencer

`endif // AXI_SEQUENCER_SV

