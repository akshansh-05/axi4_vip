// File: dma_rd_desc_driver.sv
// Description: UVM Driver for Read Descriptor Channel (MM2S: Memory-to-Stream).
//              Drives descriptor command requests and handles global read_enable.

`ifndef DMA_RD_DESC_DRIVER_SV
`define DMA_RD_DESC_DRIVER_SV

class dma_rd_desc_driver #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_driver #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item    #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) req_type;
    typedef dma_desc_agent_config #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) cfg_type;

    virtual dma_desc_if #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) vif;
    cfg_type cfg;

    `uvm_component_param_utils(dma_rd_desc_driver #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "dma_rd_desc_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("RD_DESC_DRV_CFG", "Failed to get dma_desc_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        req_type req;

        vif.rd_desc_drv_cb.read_enable <= 1'b0;
        reset_signals();

        // Wait for reset release
        wait(!vif.rst);
        @(vif.rd_desc_drv_cb);

        // Assert read_enable to activate DMA read engine
        vif.rd_desc_drv_cb.read_enable <= 1'b1;
        `uvm_info(get_type_name(), "Reset released: Asserted read_enable = 1", UVM_MEDIUM)

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info(get_type_name(), $sformatf("Driving Read Descriptor:\n%s", req.sprint()), UVM_HIGH)
            drive_descriptor(req);
            seq_item_port.item_done();
        end
    endtask : run_phase

    virtual task reset_signals();
        vif.rd_desc_drv_cb.read_desc_valid <= 1'b0;
        vif.rd_desc_drv_cb.read_desc_addr  <= '0;
        vif.rd_desc_drv_cb.read_desc_len   <= '0;
        vif.rd_desc_drv_cb.read_desc_tag   <= '0;
        vif.rd_desc_drv_cb.read_desc_id    <= '0;
        vif.rd_desc_drv_cb.read_desc_dest  <= '0;
        vif.rd_desc_drv_cb.read_desc_user  <= '0;
    endtask : reset_signals

    virtual task drive_descriptor(req_type req);
        // Optional delay before asserting valid
        repeat (req.valid_delay) @(vif.rd_desc_drv_cb);

        // Drive descriptor signals
        vif.rd_desc_drv_cb.read_desc_addr  <= req.addr;
        vif.rd_desc_drv_cb.read_desc_len   <= req.len;
        vif.rd_desc_drv_cb.read_desc_tag   <= req.tag;
        vif.rd_desc_drv_cb.read_desc_id    <= req.id;
        vif.rd_desc_drv_cb.read_desc_dest  <= req.dest;
        vif.rd_desc_drv_cb.read_desc_user  <= req.user;
        vif.rd_desc_drv_cb.read_desc_valid <= 1'b1;

        // Wait for handshake: sample at clock edge and check ready
        do begin
            @(vif.rd_desc_drv_cb);
        end while (!vif.rd_desc_drv_cb.read_desc_ready);

        // Handshake completed on this clock edge; deassert valid and clear payload
        reset_signals();
    endtask : drive_descriptor

endclass : dma_rd_desc_driver

`endif // DMA_RD_DESC_DRIVER_SV
