// File: base_test.sv
// Base test class that builds the environment, configures agents, and prints topology.
// Specific test sequences are executed in child test classes extending base_test.

`ifndef BASE_TEST_SV
`define BASE_TEST_SV

class base_test extends uvm_test;

    typedef axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) cfg_type;
    typedef axi_env          #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) env_type;

    cfg_type cfg;
    env_type env;

    `uvm_component_utils(base_test)

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 1. Create agent config and configure mode
        cfg = cfg_type::type_id::create("cfg");
        configure_agent(cfg);

        // 2. Fetch virtual interface from top testbench
        if (!uvm_config_db#(virtual axi_if #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))::get(this, "", "vif_axi", cfg.vif)) begin
            `uvm_fatal("TEST_VIF", "Failed to get vif_axi from config_db")
        end

        // 3. Set agent configuration into config_db
        uvm_config_db#(cfg_type)::set(this, "env.axi_agent*", "cfg", cfg);

        // 4. Create Environment
        env = env_type::type_id::create("env", this);
    endfunction : build_phase

    // Default agent configuration: Master Active (for RAM Standalone verification)
    // Child tests override this hook to change agent mode
    virtual function void configure_agent(cfg_type cfg);
        cfg.is_active = UVM_ACTIVE;
        cfg.is_master = 1'b1;
    endfunction : configure_agent

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction : end_of_elaboration_phase

    virtual task run_phase(uvm_phase phase);
        // Base test topology verification and environment build. 
    endtask : run_phase

endclass : base_test

`endif // BASE_TEST_SV
