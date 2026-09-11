// File: axi_sanity_test.sv
// Test class executing the AXI sanity sequence (4-beat write followed by 4-beat read) on axi_ram.

`ifndef AXI_SANITY_TEST_SV
`define AXI_SANITY_TEST_SV

class axi_sanity_test extends base_test;

    typedef axi_wr_sanity_seq #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) wr_seq_type;
    typedef axi_rd_sanity_seq #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) rd_seq_type;

    `uvm_component_utils(axi_sanity_test)

    function new(string name = "axi_sanity_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new
    
    virtual task run_phase(uvm_phase phase);
        wr_seq_type wr_seq;
        rd_seq_type rd_seq;

        wr_seq = wr_seq_type::type_id::create("wr_seq");
        rd_seq = rd_seq_type::type_id::create("rd_seq");

        phase.raise_objection(this, "Starting AXI Sanity Test");
        `uvm_info("SANITY_TEST", "Executing Write and Read sanity sequences on axi_ram", UVM_LOW)

        // 1. Launch Write sanity sequence on Write Agent Sequencer
        wr_seq.start(env.axi_wr_agent.seqr);
        `uvm_info("SANITY_TEST", "Executing Write sanity sequence", UVM_MEDIUM)

        // 2. Launch Read sanity sequence on Read Agent Sequencer
        rd_seq.start(env.axi_rd_agent.seqr);
        `uvm_info("SANITY_TEST", "Executing Read sanity sequence", UVM_MEDIUM)

        #100; // Small drain time to observe bus idle in waveforms
        `uvm_info("SANITY_TEST", "Sanity Test Completed Successfully!", UVM_MEDIUM)
        phase.drop_objection(this, "Completed AXI Sanity Test");
    endtask : run_phase

endclass : axi_sanity_test

`endif // AXI_SANITY_TEST_SV
