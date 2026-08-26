// File: axi_virtual_seq_base.sv
// Base class for top-level virtual sequences coordinating across all agents.

`ifndef AXI_VIRTUAL_SEQ_BASE_SV
`define AXI_VIRTUAL_SEQ_BASE_SV

class axi_virtual_seq_base extends uvm_sequence;

    `uvm_object_utils(axi_virtual_seq_base)

    function new(string name = "axi_virtual_seq_base");
        super.new(name);
    endfunction : new

endclass : axi_virtual_seq_base

`endif // AXI_VIRTUAL_SEQ_BASE_SV
