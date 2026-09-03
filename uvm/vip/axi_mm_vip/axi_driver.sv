// File: axi_driver.sv
// UVM Driver for AXI4 Memory-Mapped bus.
// Supports Master mode (driving write/read burst requests) and Slave reactive mode.

`ifndef AXI_DRIVER_SV
`define AXI_DRIVER_SV

class axi_driver #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_driver #(axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH));

    typedef axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) req_type;

    virtual axi_if #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) vif;
    axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) cfg;

    `uvm_component_param_utils(axi_driver #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    // Retrieve config object and extract virtual interface handle
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("DRV_CFG", "Failed to get axi_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    // Main Run Phase
    virtual task run_phase(uvm_phase phase);
        reset_signals();

        // Wait for active-high reset to drop
        wait(!vif.rst);
        @(vif.drv_cb);

        if (cfg.is_master) begin
            run_master();
        end else begin
            run_slave();
        end
    endtask : run_phase

    // Reset Master Driven Signals (Used when verifying Slave DUT e.g. RAM)
    virtual task reset_master_signals();
        vif.drv_cb.awid    <= '0;
        vif.drv_cb.awaddr  <= '0;
        vif.drv_cb.awlen   <= '0;
        vif.drv_cb.awsize  <= '0;
        vif.drv_cb.awburst <= '0;
        vif.drv_cb.awvalid <= 1'b0;

        vif.drv_cb.wdata   <= '0;
        vif.drv_cb.wstrb   <= '0;
        vif.drv_cb.wlast   <= 1'b0;
        vif.drv_cb.wvalid  <= 1'b0;

        vif.drv_cb.bready  <= 1'b0;

        vif.drv_cb.arid    <= '0;
        vif.drv_cb.araddr  <= '0;
        vif.drv_cb.arlen   <= '0;
        vif.drv_cb.arsize  <= '0;
        vif.drv_cb.arburst <= '0;
        vif.drv_cb.arvalid <= 1'b0;

        vif.drv_cb.rready  <= 1'b0;
    endtask : reset_master_signals

    // Reset Slave Driven Signals (Used when verifying Master DUT e.g. DMA)
    virtual task reset_slave_signals();
        vif.slv_drv_cb.awready <= 1'b0;

        vif.slv_drv_cb.wready  <= 1'b0;

        vif.slv_drv_cb.bid     <= '0;
        vif.slv_drv_cb.bresp   <= '0;
        vif.slv_drv_cb.bvalid  <= 1'b0;

        vif.slv_drv_cb.arready <= 1'b0;

        vif.slv_drv_cb.rid     <= '0;
        vif.slv_drv_cb.rdata   <= '0;
        vif.slv_drv_cb.rresp   <= '0;
        vif.slv_drv_cb.rlast   <= 1'b0;
        vif.slv_drv_cb.rvalid  <= 1'b0;
    endtask : reset_slave_signals

    // Top Reset Task branching based on agent role
    virtual task reset_signals();
        if (cfg.is_master) begin
            reset_master_signals();
        end else begin
            reset_slave_signals();
        end
    endtask : reset_signals

    // Master execution loop
    virtual task run_master();
        forever begin
            // 1. Fetch next item from Sequencer
            seq_item_port.get_next_item(req);

            `uvm_info("DRV", $sformatf("Driving %s burst: addr=0x%04h, len=%0d beats",
                      (req.trans_type == AXI_WRITE) ? "WRITE" : "READ", req.addr, req.len + 1), UVM_LOW)

            // 2. Drive transaction to pins
            if (req.trans_type == AXI_WRITE) begin
                drive_master_write(req);
            end else begin
                drive_master_read(req);
            end

            // 3. Acknowledge transaction done to Sequencer
            seq_item_port.item_done();
        end
    endtask : run_master

    // Master Write Transaction (Concurrently drives AW, W, and collects B response)
    virtual task drive_master_write(req_type req);
        fork
            // Thread 1: Write Address Channel (AW)
            begin
                repeat (req.addr_delay) @(vif.drv_cb);

                vif.drv_cb.awid    <= req.id;
                vif.drv_cb.awaddr  <= req.addr;
                vif.drv_cb.awlen   <= req.len;
                vif.drv_cb.awsize  <= req.size;
                vif.drv_cb.awburst <= req.burst;
                vif.drv_cb.awvalid <= 1'b1;

                do begin
                    @(vif.drv_cb);
                end while (!vif.drv_cb.awready);

                vif.drv_cb.awvalid <= 1'b0;
            end

            // Thread 2: Write Data Channel (W)
            begin
                for (int i = 0; i <= req.len; i++) begin
                    if (req.data_delay.size() > i)
                        repeat (req.data_delay[i]) @(vif.drv_cb);

                    vif.drv_cb.wdata  <= req.data[i];
                    vif.drv_cb.wstrb  <= req.strb[i];
                    vif.drv_cb.wlast  <= (i == req.len);
                    vif.drv_cb.wvalid <= 1'b1;

                    do begin
                        @(vif.drv_cb);
                    end while (!vif.drv_cb.wready);
                end

                vif.drv_cb.wvalid <= 1'b0;
                vif.drv_cb.wlast  <= 1'b0;
            end

            // Thread 3: Write Response Channel (B)
            begin
                vif.drv_cb.bready <= 1'b1;
                do begin
                    @(vif.drv_cb);
                end while (!vif.drv_cb.bvalid);

                // Capture and print Write Response received from DUT
                req.bid   = vif.drv_cb.bid;
                req.bresp = vif.drv_cb.bresp;
                `uvm_info("DRV_WR_RESP", $sformatf("DUT Write Response: bid=0x%0h, bresp=2'b%0b (%s)",
                          req.bid, req.bresp, (req.bresp == 2'b00) ? "OKAY" : "ERROR"), UVM_LOW)
                vif.drv_cb.bready <= 1'b0;
            end
        join
    endtask : drive_master_write

    // Master Read Transaction (Drives AR and collects R data beats)
    virtual task drive_master_read(req_type req);
        // Step 1: Drive Read Address Channel (AR)
        repeat (req.addr_delay) @(vif.drv_cb);

        vif.drv_cb.arid    <= req.id;
        vif.drv_cb.araddr  <= req.addr;
        vif.drv_cb.arlen   <= req.len;
        vif.drv_cb.arsize  <= req.size;
        vif.drv_cb.arburst <= req.burst;
        vif.drv_cb.arvalid <= 1'b1;

        do begin
            @(vif.drv_cb);
        end while (!vif.drv_cb.arready);

        vif.drv_cb.arvalid <= 1'b0;

        // Step 2: Receive Read Data Channel (R) beats
        req.data  = new[req.len + 1];
        req.rresp = new[req.len + 1];
        req.rid   = new[req.len + 1];

        vif.drv_cb.rready <= 1'b1;
        for (int i = 0; i <= req.len; i++) begin
            do begin
                @(vif.drv_cb);
            end while (!vif.drv_cb.rvalid);

            req.data[i]  = vif.drv_cb.rdata;
            req.rresp[i] = vif.drv_cb.rresp;
            req.rid[i]   = vif.drv_cb.rid;

            `uvm_info("DRV_RD_DATA", $sformatf("DUT Read Beat [%0d/%0d]: rdata=0x%08h, rresp=2'b%0b, rid=0x%0h",
                      i, req.len, req.data[i], req.rresp[i], req.rid[i]), UVM_LOW)
        end

        vif.drv_cb.rready <= 1'b0;
    endtask : drive_master_read

    // Placeholder for Slave reactive loop (used in standalone DMA verification)
    virtual task run_slave();
        `uvm_info("DRV", "AXI Slave mode running...", UVM_MEDIUM)
        forever @(vif.slv_drv_cb);
    endtask : run_slave

endclass : axi_driver

`endif // AXI_DRIVER_SV
