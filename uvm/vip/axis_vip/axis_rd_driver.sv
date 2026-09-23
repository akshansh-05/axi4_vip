// File: axis_rd_driver.sv
// Description: UVM Driver for AXI4-Stream Read Channel (Slave / Consumer mode).
//              Connects to the DUT's m_axis_read_data_* interface, controlling
//              the TREADY handshake signal and modeling receiver backpressure.

`ifndef AXIS_RD_DRIVER_SV
`define AXIS_RD_DRIVER_SV

class axis_rd_driver #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_driver #(axis_seq_item #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef axis_seq_item     #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) req_type;
    typedef axis_agent_config #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) cfg_type;

    virtual axis_if #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) vif;
    cfg_type cfg;

    `uvm_component_param_utils(axis_rd_driver #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "axis_rd_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("AXIS_RD_DRV_CFG", "Failed to get axis_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        reset_signals();

        wait(!vif.rst);
        @(vif.slv_drv_cb);

        if (cfg.ready_always_high) begin
            run_always_ready();
        end else begin
            run_backpressure();
        end
    endtask : run_phase

    // Deassert TREADY during reset
    virtual task reset_signals();
        vif.slv_drv_cb.tready <= 1'b0;
    endtask : reset_signals

    // Mode 1: TREADY held permanently high — zero backpressure consumer.
    // The DUT can transfer data on every clock cycle without stalling.
    virtual task run_always_ready();
        vif.slv_drv_cb.tready <= 1'b1;

        // Hold TREADY high forever; monitor handles packet collection.
        // We still watch for reset to re-deassert TREADY cleanly.
        forever begin
            @(vif.slv_drv_cb);
            if (vif.rst) begin
                vif.slv_drv_cb.tready <= 1'b0;
                wait(!vif.rst);
                @(vif.slv_drv_cb);
                vif.slv_drv_cb.tready <= 1'b1;
            end
        end
    endtask : run_always_ready

    // Mode 2: Backpressure consumer — wait for DUT to assert TVALID, then
    // delay 'default_ready_delay' cycles before asserting TREADY for one cycle.
    // This models a slow receiver that cannot keep up with the producer.
    virtual task run_backpressure();
        forever begin
            @(vif.slv_drv_cb);

            if (vif.rst) begin
                vif.slv_drv_cb.tready <= 1'b0;
                wait(!vif.rst);
                @(vif.slv_drv_cb);
            end else if (vif.slv_drv_cb.tvalid) begin
                // DUT is presenting data; apply configurable delay before accepting
                if (cfg.default_ready_delay > 0) begin
                    repeat (cfg.default_ready_delay) @(vif.slv_drv_cb);
                end

                // Pulse TREADY for exactly one clock cycle to complete handshake
                vif.slv_drv_cb.tready <= 1'b1;
                @(vif.slv_drv_cb);
                vif.slv_drv_cb.tready <= 1'b0;
            end
        end
    endtask : run_backpressure

endclass : axis_rd_driver

`endif // AXIS_RD_DRIVER_SV
