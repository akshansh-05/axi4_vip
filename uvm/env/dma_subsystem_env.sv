// File: dma_subsystem_env.sv
// Description: Top-level verification environment for the AXI4 DMA Subsystem.
//              Integrates AXI-MM, DMA Descriptors, AXI-Stream agents,
//              Coverage Model, and End-to-End Scoreboard.

`ifndef DMA_SUBSYSTEM_ENV_SV
`define DMA_SUBSYSTEM_ENV_SV

class dma_subsystem_env #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_env;

    typedef axi_wr_agent      #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) wr_agent_type;
    typedef axi_rd_agent      #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) rd_agent_type;
    typedef dma_rd_desc_agent #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) dma_rd_desc_agent_type;
    typedef dma_wr_desc_agent #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) dma_wr_desc_agent_type;
    typedef axi_coverage      #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) cov_type;
    // typedef axi_scoreboard #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) scb_type;

    wr_agent_type          axi_wr_agent;
    rd_agent_type          axi_rd_agent;
    dma_rd_desc_agent_type dma_rd_desc_agent;
    dma_wr_desc_agent_type dma_wr_desc_agent;
    cov_type               cov;
    // scb_type            scb;

    `uvm_component_param_utils(dma_subsystem_env #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH, LEN_WIDTH, TAG_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "dma_subsystem_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axi_wr_agent      = wr_agent_type::type_id::create("axi_wr_agent", this);
        axi_rd_agent      = rd_agent_type::type_id::create("axi_rd_agent", this);
        dma_rd_desc_agent = dma_rd_desc_agent_type::type_id::create("dma_rd_desc_agent", this);
        dma_wr_desc_agent = dma_wr_desc_agent_type::type_id::create("dma_wr_desc_agent", this);
        cov               = cov_type::type_id::create("cov", this);
        // scb            = scb_type::type_id::create("scb", this);
    endfunction : build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Connect both Write and Read Monitor analysis ports to Coverage Subscriber
        axi_wr_agent.mon.ap.connect(cov.analysis_export);
        axi_rd_agent.mon.ap.connect(cov.analysis_export);
        // axi_wr_agent.mon.ap.connect(scb.analysis_export);
        // axi_rd_agent.mon.ap.connect(scb.analysis_export);
    endfunction : connect_phase

endclass : dma_subsystem_env

// Backward-compatibility alias
// typedef dma_subsystem_env axi_env;

`endif // DMA_SUBSYSTEM_ENV_SV
