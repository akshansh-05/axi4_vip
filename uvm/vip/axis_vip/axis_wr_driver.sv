// File: axis_wr_driver.sv
// Description: UVM Driver for AXI4-Stream Write Channel (Master / Producer mode).
//              Drives stream packets (TDATA, TKEEP, TVALID, TLAST, TID, TDEST, TUSER)
//              into the DUT's s_axis_write_data_* interface, respecting TREADY backpressure.

`ifndef AXIS_WR_DRIVER_SV
`define AXIS_WR_DRIVER_SV

class axis_wr_driver #(
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

    `uvm_component_param_utils(axis_wr_driver #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "axis_wr_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("AXIS_WR_DRV_CFG", "Failed to get axis_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        reset_signals();

        wait(!vif.rst);
        @(vif.mst_drv_cb);

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info(get_type_name(), $sformatf("Driving stream write packet: %0d beats, ID=0x%0x, DEST=0x%0x",
                      req.data.size(), req.id, req.dest), UVM_HIGH)
            drive_packet(req);
            seq_item_port.item_done();
        end
    endtask : run_phase

    // Initialize all master-driven stream signals to inactive
    virtual task reset_signals();
        vif.mst_drv_cb.tdata  <= '0;
        vif.mst_drv_cb.tkeep  <= '0;
        vif.mst_drv_cb.tvalid <= 1'b0;
        vif.mst_drv_cb.tlast  <= 1'b0;
        vif.mst_drv_cb.tid    <= '0;
        vif.mst_drv_cb.tdest  <= '0;
        vif.mst_drv_cb.tuser  <= '0;
    endtask : reset_signals

    // Drive each beat of an AXI-Stream packet sequentially
    virtual task drive_packet(req_type item);
        int num_beats;
        num_beats = item.data.size();

        for (int i = 0; i < num_beats; i++) begin
            // Optional inter-beat delay (idle cycles where TVALID remains deasserted)
            if (item.delay.size() > i && item.delay[i] > 0) begin
                vif.mst_drv_cb.tvalid <= 1'b0;
                repeat (item.delay[i]) @(vif.mst_drv_cb);
            end

            // Drive beat payload and attributes
            vif.mst_drv_cb.tdata  <= item.data[i];
            vif.mst_drv_cb.tkeep  <= (item.keep.size() > i) ? item.keep[i] : {KEEP_WIDTH{1'b1}};
            vif.mst_drv_cb.tlast  <= (i == num_beats - 1) ? item.last : 1'b0;
            vif.mst_drv_cb.tid    <= item.id;
            vif.mst_drv_cb.tdest  <= item.dest;
            vif.mst_drv_cb.tuser  <= (item.user.size() > i) ? item.user[i] : '0;
            vif.mst_drv_cb.tvalid <= 1'b1;

            // Wait for handshake: TVALID and TREADY sampled high at clock edge
            do begin
                @(vif.mst_drv_cb);
            end while (!vif.mst_drv_cb.tready);
        end

        // Clean up interface after packet completes
        vif.mst_drv_cb.tvalid <= 1'b0;
        vif.mst_drv_cb.tlast  <= 1'b0;
        vif.mst_drv_cb.tdata  <= '0;
        vif.mst_drv_cb.tkeep  <= '0;
    endtask : drive_packet

endclass : axis_wr_driver

`endif // AXIS_WR_DRIVER_SV
