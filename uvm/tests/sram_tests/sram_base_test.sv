// File: sram_base_test.sv
// Description: Dedicated base test class for SRAM Standalone verification (RAM_STANDALONE).
//              Builds the block-level axi_ram_env, configures AXI write and read agents as
//              active masters driving the axi_ram DUT, and prints the component topology.

`ifndef SRAM_BASE_TEST_SV
`define SRAM_BASE_TEST_SV

class sram_base_test extends uvm_test;

    typedef axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) cfg_type;
    typedef axi_ram_env      #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) env_type;

    cfg_type cfg_wr;
    cfg_type cfg_rd;
    env_type env;

    `uvm_component_utils(sram_base_test)

    function new(string name = "sram_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 1. Create agent configurations
        cfg_wr = cfg_type::type_id::create("cfg_wr");
        cfg_rd = cfg_type::type_id::create("cfg_rd");
        configure_agents(cfg_wr, cfg_rd);

        // 2. Fetch AXI virtual interface from top testbench
        if (!uvm_config_db#(virtual axi_if #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))::get(this, "", "vif_axi", cfg_wr.vif)) begin
            if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif_axi", cfg_wr.vif)) begin
                `uvm_fatal("SRAM_BASE_VIF", "Failed to get vif_axi from config_db")
            end
        end
        cfg_rd.vif = cfg_wr.vif;

        // 3. Set configurations into config_db for environment agents
        uvm_config_db#(cfg_type)::set(this, "env.axi_wr_agent*", "cfg", cfg_wr);
        uvm_config_db#(cfg_type)::set(this, "env.axi_rd_agent*", "cfg", cfg_rd);

        // 4. Create SRAM Environment (axi_ram_env)
        env = env_type::type_id::create("env", this);
    endfunction : build_phase

    // Default configuration: AXI Agents are Active Masters driving SRAM
    virtual function void configure_agents(cfg_type c_wr, cfg_type c_rd);
        c_wr.is_active = UVM_ACTIVE;
        c_wr.is_master = 1'b1;
        c_rd.is_active = UVM_ACTIVE;
        c_rd.is_master = 1'b1;
    endfunction : configure_agents

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction : end_of_elaboration_phase

    virtual task run_phase(uvm_phase phase);
        // Base test serves as foundation for child tests; no stimulus executed here.
    endtask : run_phase

endclass : sram_base_test

`endif // SRAM_BASE_TEST_SV
