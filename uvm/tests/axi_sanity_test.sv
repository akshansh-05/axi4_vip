// File: axi_sanity_test.sv
// Test class executing the AXI sanity sequence (4-beat write followed by 4-beat read) on axi_ram.

`ifndef AXI_SANITY_TEST_SV
`define AXI_SANITY_TEST_SV

class axi_sanity_test extends base_test;

    typedef axi_sanity_seq #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) seq_type;

    `uvm_component_utils(axi_sanity_test)

    function new(string name = "axi_sanity_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        seq_type seq;
        seq = seq_type::type_id::create("seq");

        phase.raise_objection(this, "Starting AXI Sanity Test");
        `uvm_info("SANITY_TEST", "Executing axi_sanity_seq on axi_ram...", UVM_LOW)

        // Launch sanity sequence on the AXI Master sequencer
        seq.start(env.axi_agent.seqr);

        #100; // Small drain time to observe bus idle in waveforms
        `uvm_info("SANITY_TEST", "Sanity Test Completed Successfully!", UVM_LOW)
        phase.drop_objection(this, "Completed AXI Sanity Test");
    endtask : run_phase

endclass : axi_sanity_test

`endif // AXI_SANITY_TEST_SV
