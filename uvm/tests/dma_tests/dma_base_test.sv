// File: dma_base_test.sv
// Description: Dedicated base test class for DMA Standalone and Full Subsystem verification.
//              Builds the top dma_subsystem_env, configures descriptor agents as active masters,
//              configures AXI agents as passive monitors (or slave responders), retrieves
//              vif_axi and vif_desc, and prints the component topology.

`ifndef DMA_BASE_TEST_SV
`define DMA_BASE_TEST_SV

class dma_base_test extends uvm_test;

    typedef axi_agent_config      #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) cfg_type;
    typedef dma_desc_agent_config #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) dma_cfg_type;
    typedef dma_subsystem_env     #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH) env_type;

    cfg_type     cfg_wr;
    cfg_type     cfg_rd;
    dma_cfg_type cfg_dma_rd;
    dma_cfg_type cfg_dma_wr;
    env_type     env;

    `uvm_component_utils(dma_base_test)

    function new(string name = "dma_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 1. Create agent configurations
        cfg_wr     = cfg_type::type_id::create("cfg_wr");
        cfg_rd     = cfg_type::type_id::create("cfg_rd");
        cfg_dma_rd = dma_cfg_type::type_id::create("cfg_dma_rd");
        cfg_dma_wr = dma_cfg_type::type_id::create("cfg_dma_wr");
        configure_agents(cfg_wr, cfg_rd, cfg_dma_rd, cfg_dma_wr);

        // 2. Fetch AXI virtual interface
        if (!uvm_config_db#(virtual axi_if #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))::get(this, "", "vif_axi", cfg_wr.vif)) begin
            if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif_axi", cfg_wr.vif)) begin
                `uvm_fatal("DMA_BASE_VIF", "Failed to get vif_axi from config_db")
            end
        end
        cfg_rd.vif = cfg_wr.vif;

        // 3. Fetch Descriptor virtual interface
        if (!uvm_config_db#(virtual dma_desc_if #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))::get(this, "", "vif_desc", cfg_dma_rd.vif)) begin
            if (!uvm_config_db#(virtual dma_desc_if)::get(this, "", "vif_desc", cfg_dma_rd.vif)) begin
                `uvm_fatal("DMA_BASE_VIF", "Failed to get vif_desc from config_db")
            end
        end
        cfg_dma_wr.vif = cfg_dma_rd.vif;

        // 4. Set configurations into config_db for environment agents
        uvm_config_db#(cfg_type)::set(this, "env.axi_wr_agent*", "cfg", cfg_wr);
        uvm_config_db#(cfg_type)::set(this, "env.axi_rd_agent*", "cfg", cfg_rd);
        uvm_config_db#(dma_cfg_type)::set(this, "env.dma_rd_desc_agent*", "cfg", cfg_dma_rd);
        uvm_config_db#(dma_cfg_type)::set(this, "env.dma_wr_desc_agent*", "cfg", cfg_dma_wr);

        // 5. Create Environment
        env = env_type::type_id::create("env", this);
    endfunction : build_phase

    // Default configuration for DMA Standalone verification:
    // AXI-MM agents act as Active Slave Responders (is_active = UVM_ACTIVE, is_master = 0).
    // Descriptor channels driven actively by testbench (is_active = UVM_ACTIVE).
    // Future Subsystem tests can override this virtual method to set AXI agents to UVM_PASSIVE.
    virtual function void configure_agents(
        cfg_type c_wr, cfg_type c_rd,
        dma_cfg_type c_dma_rd, dma_cfg_type c_dma_wr
    );
        c_wr.is_active     = UVM_ACTIVE;
        c_wr.is_master     = 1'b0; // Active Slave Responder
        c_rd.is_active     = UVM_ACTIVE;
        c_rd.is_master     = 1'b0; // Active Slave Responder
        c_dma_rd.is_active = UVM_ACTIVE;
        c_dma_wr.is_active = UVM_ACTIVE;
    endfunction : configure_agents

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction : end_of_elaboration_phase

    virtual task run_phase(uvm_phase phase);
        // Base test serves as foundation for child tests; no stimulus executed here.
    endtask : run_phase

endclass : dma_base_test

`endif // DMA_BASE_TEST_SV
