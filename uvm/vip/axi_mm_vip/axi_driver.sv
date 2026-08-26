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

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("DRV_CFG", "Failed to get axi_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

/*    virtual task run_phase(uvm_phase phase);
        reset_signals();

        // Wait for reset release before operating
        wait(!vif.rst);
        @(posedge vif.clk);

        if (cfg.is_master) begin
            run_master();
        end else begin
            run_slave();
        end
    endtask : run_phase

    // Initialize all master driven signals to inactive state
    virtual task reset_signals();
        vif.awid    <= '0;
        vif.awaddr  <= '0;
        vif.awlen   <= '0;
        vif.awsize  <= '0;
        vif.awburst <= '0;
        vif.awvalid <= 1'b0;

        vif.wdata   <= '0;
        vif.wstrb   <= '0;
        vif.wlast   <= 1'b0;
        vif.wvalid  <= 1'b0;

        vif.bready  <= 1'b0;

        vif.arid    <= '0;
        vif.araddr  <= '0;
        vif.arlen   <= '0;
        vif.arsize  <= '0;
        vif.arburst <= '0;
        vif.arvalid <= 1'b0;

        vif.rready  <= 1'b0;
    endtask : reset_signals

    // Master execution loop
    virtual task run_master();
        forever begin
            seq_item_port.get_next_item(req);

            if (req.trans_type == AXI_WRITE) begin
                drive_master_write(req);
            end else begin
                drive_master_read(req);
            end

            seq_item_port.item_done();
        end
    endtask : run_master

    // Master Write Transaction (Drives AW, W, and collects B response)
    virtual task drive_master_write(req_type req);
        fork
            // Thread 1: Write Address Channel (AW)
            begin
                repeat (req.addr_delay) @(posedge vif.clk);

                vif.awid    <= req.id;
                vif.awaddr  <= req.addr;
                vif.awlen   <= req.len;
                vif.awsize  <= req.size;
                vif.awburst <= req.burst;
                vif.awvalid <= 1'b1;

                do begin
                    @(posedge vif.clk);
                end while (!vif.awready);

                vif.awvalid <= 1'b0;
            end

            // Thread 2: Write Data Channel (W)
            begin
                for (int i = 0; i <= req.len; i++) begin
                    if (req.data_delay.size() > i)
                        repeat (req.data_delay[i]) @(posedge vif.clk);

                    vif.wdata  <= req.data[i];
                    vif.wstrb  <= req.strb[i];
                    vif.wlast  <= (i == req.len);
                    vif.wvalid <= 1'b1;

                    do begin
                        @(posedge vif.clk);
                    end while (!vif.wready);
                end

                vif.wvalid <= 1'b0;
                vif.wlast  <= 1'b0;
            end

            // Thread 3: Write Response Channel (B)
            begin
                vif.bready <= 1'b1;
                do begin
                    @(posedge vif.clk);
                end while (!vif.bvalid);

                req.bid   = vif.bid;
                req.bresp = vif.bresp;
                vif.bready <= 1'b0;
            end
        join
    endtask : drive_master_write

    // Master Read Transaction (Drives AR and collects R data beats)
    virtual task drive_master_read(req_type req);
        // Step 1: Drive Read Address Channel (AR)
        repeat (req.addr_delay) @(posedge vif.clk);

        vif.arid    <= req.id;
        vif.araddr  <= req.addr;
        vif.arlen   <= req.len;
        vif.arsize  <= req.size;
        vif.arburst <= req.burst;
        vif.arvalid <= 1'b1;

        do begin
            @(posedge vif.clk);
        end while (!vif.arready);

        vif.arvalid <= 1'b0;

        // Step 2: Receive Read Data Channel (R) beats
        req.data  = new[req.len + 1];
        req.rresp = new[req.len + 1];
        req.rid   = new[req.len + 1];

        vif.rready <= 1'b1;
        for (int i = 0; i <= req.len; i++) begin
            do begin
                @(posedge vif.clk);
            end while (!vif.rvalid);

            req.data[i]  = vif.rdata;
            req.rresp[i] = vif.rresp;
            req.rid[i]   = vif.rid;
        end

        vif.rready <= 1'b0;
    endtask : drive_master_read

    // Placeholder for Slave reactive loop (used in standalone DMA verification)
    virtual task run_slave();
        `uvm_info("DRV", "AXI Slave mode running...", UVM_MEDIUM)
        forever @(posedge vif.clk);
    endtask : run_slave */

endclass : axi_driver

`endif // AXI_DRIVER_SV
