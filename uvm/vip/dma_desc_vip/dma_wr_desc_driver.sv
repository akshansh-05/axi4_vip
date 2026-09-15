// File: dma_wr_desc_driver.sv
// Description: UVM Driver for Write Descriptor Channel (S2MM: Stream-to-Memory).
//              Drives write descriptor command requests and handles global write_enable/abort.

`ifndef DMA_WR_DESC_DRIVER_SV
`define DMA_WR_DESC_DRIVER_SV

class dma_wr_desc_driver #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_driver #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item     #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) req_type;
    typedef dma_desc_agent_config #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) cfg_type;

    virtual dma_desc_if #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) vif;
    cfg_type cfg;

    `uvm_component_param_utils(dma_wr_desc_driver #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "dma_wr_desc_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("WR_DESC_DRV_CFG", "Failed to get dma_desc_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        req_type req;

        vif.wr_desc_drv_cb.write_enable <= 1'b0;
        vif.wr_desc_drv_cb.write_abort  <= 1'b0;
        reset_signals();

        // Wait for reset release
        wait(!vif.rst);
        @(vif.wr_desc_drv_cb);

        // Assert write_enable to activate DMA write engine
        vif.wr_desc_drv_cb.write_enable <= 1'b1;
        vif.wr_desc_drv_cb.write_abort  <= 1'b0;
        `uvm_info(get_type_name(), "Reset released: Asserted write_enable = 1, write_abort = 0", UVM_MEDIUM)

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info(get_type_name(), $sformatf("Driving Write Descriptor:\n%s", req.sprint()), UVM_HIGH)
            drive_descriptor(req);
            seq_item_port.item_done();
        end
    endtask : run_phase

    virtual task reset_signals();
        vif.wr_desc_drv_cb.write_desc_valid <= 1'b0;
        vif.wr_desc_drv_cb.write_desc_addr  <= '0;
        vif.wr_desc_drv_cb.write_desc_len   <= '0;
        vif.wr_desc_drv_cb.write_desc_tag   <= '0;
    endtask : reset_signals

    virtual task drive_descriptor(req_type req);
        // Optional delay before asserting valid
        repeat (req.valid_delay) @(vif.wr_desc_drv_cb);

        // Drive descriptor signals
        vif.wr_desc_drv_cb.write_desc_addr  <= req.addr;
        vif.wr_desc_drv_cb.write_desc_len   <= req.len;
        vif.wr_desc_drv_cb.write_desc_tag   <= req.tag;
        vif.wr_desc_drv_cb.write_desc_valid <= 1'b1;

        // Wait for handshake: sample at clock edge and check ready
        do begin
            @(vif.wr_desc_drv_cb);
        end while (!vif.wr_desc_drv_cb.write_desc_ready);

        // Handshake completed on this clock edge; deassert valid and clear payload
        reset_signals();
    endtask : drive_descriptor

endclass : dma_wr_desc_driver

`endif // DMA_WR_DESC_DRIVER_SV
