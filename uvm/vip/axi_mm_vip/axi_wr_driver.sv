// File: axi_wr_driver.sv
// Dedicated UVM Driver for AXI4 Memory-Mapped Write Channels (AW, W, B).

`ifndef AXI_WR_DRIVER_SV
`define AXI_WR_DRIVER_SV

class axi_wr_driver #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_driver #(axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH));

    typedef axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) req_type;

    virtual axi_if #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) vif;
    axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) cfg;

    // Slave mode internal tracking structures
    typedef struct {
        bit [ID_WIDTH-1:0]   id;
        bit [ADDR_WIDTH-1:0] addr;
        bit [7:0]            len;
        bit [2:0]            size;
        bit [1:0]            burst;
    } slv_aw_info_t;

    slv_aw_info_t slv_aw_q[$];
    int unsigned  slv_w_bursts_done = 0;

    `uvm_component_param_utils(axi_wr_driver #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_wr_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("WR_DRV_CFG", "Failed to get axi_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        reset_signals();

        wait(!vif.rst);
        @(vif.wr_drv_cb);

        if (cfg.is_master) begin
            run_master();
        end else begin
            run_slave();
        end
    endtask : run_phase

    virtual task reset_master_signals();
        vif.wr_drv_cb.awid    <= '0;
        vif.wr_drv_cb.awaddr  <= '0;
        vif.wr_drv_cb.awlen   <= '0;
        vif.wr_drv_cb.awsize  <= '0;
        vif.wr_drv_cb.awburst <= '0;
        vif.wr_drv_cb.awvalid <= 1'b0;

        vif.wr_drv_cb.wdata   <= '0;
        vif.wr_drv_cb.wstrb   <= '0;
        vif.wr_drv_cb.wlast   <= 1'b0;
        vif.wr_drv_cb.wvalid  <= 1'b0;

        vif.wr_drv_cb.bready  <= 1'b0;
    endtask : reset_master_signals

    virtual task reset_slave_signals();
        vif.wr_slv_drv_cb.awready <= 1'b0;
        vif.wr_slv_drv_cb.wready  <= 1'b0;
        vif.wr_slv_drv_cb.bid     <= '0;
        vif.wr_slv_drv_cb.bresp   <= '0;
        vif.wr_slv_drv_cb.bvalid  <= 1'b0;
        slv_aw_q.delete();
        slv_w_bursts_done = 0;
    endtask : reset_slave_signals

    virtual task reset_signals();
        if (cfg.is_master) begin
            reset_master_signals();
        end else begin
            reset_slave_signals();
        end
    endtask : reset_signals

    virtual task run_master();
        forever begin
            seq_item_port.get_next_item(req);

            `uvm_info("WR_DRV", $sformatf("Driving transaction received from sequencer:\n%s", req.sprint()), UVM_LOW)

            drive_master_write(req);

            seq_item_port.item_done();
        end
    endtask : run_master

    virtual task drive_master_write(req_type req);
        fork
            // Thread 1: Write Address Channel (AW)
            begin
                repeat (req.addr_delay) @(vif.wr_drv_cb);

                vif.wr_drv_cb.awid    <= req.id;
                vif.wr_drv_cb.awaddr  <= req.addr;
                vif.wr_drv_cb.awlen   <= req.len;
                vif.wr_drv_cb.awsize  <= req.size;
                vif.wr_drv_cb.awburst <= req.burst;
                vif.wr_drv_cb.awvalid <= 1'b1;

                do begin
                    @(vif.wr_drv_cb);
                end while (!vif.wr_drv_cb.awready);

                vif.wr_drv_cb.awvalid <= 1'b0;
            end

            // Thread 2: Write Data Channel (W)
            begin
                for (int i = 0; i <= req.len; i++) begin
                    if (req.data_delay.size() > i)
                        repeat (req.data_delay[i]) @(vif.wr_drv_cb);

                    vif.wr_drv_cb.wdata  <= req.data[i];
                    vif.wr_drv_cb.wstrb  <= req.strb[i];
                    vif.wr_drv_cb.wlast  <= (i == req.len);
                    vif.wr_drv_cb.wvalid <= 1'b1;

                    do begin
                        @(vif.wr_drv_cb);
                    end while (!vif.wr_drv_cb.wready);
                end

                vif.wr_drv_cb.wvalid <= 1'b0;
                vif.wr_drv_cb.wlast  <= 1'b0;
            end

            // Thread 3: Write Response Channel (B)
            begin
                vif.wr_drv_cb.bready <= 1'b1;
                do begin
                    @(vif.wr_drv_cb);
                end while (!vif.wr_drv_cb.bvalid);

                req.bid   = vif.wr_drv_cb.bid;
                req.bresp = vif.wr_drv_cb.bresp;
                `uvm_info("WR_DRV_RESP", $sformatf("DUT Write Response: bid=0x%0h, bresp=2'b%0b (%s)",
                          req.bid, req.bresp, (req.bresp == 2'b00) ? "OKAY" : "ERROR"), UVM_LOW)
                vif.wr_drv_cb.bready <= 1'b0;
            end
        join
    endtask : drive_master_write

    virtual task run_slave();
        `uvm_info("WR_DRV", "AXI Slave Write mode running (READY tied high).", UVM_LOW)
        fork
            slave_handle_aw();
            slave_handle_w();
            slave_handle_b();
        join
    endtask : run_slave

    // Slave AW Channel: AWREADY tied HIGH, captures address descriptor on awvalid
    virtual task slave_handle_aw();
        slv_aw_info_t aw_info;
        vif.wr_slv_drv_cb.awready <= 1'b1;
        forever begin
            @(vif.wr_slv_drv_cb);
            if (vif.wr_slv_drv_cb.awvalid) begin
                aw_info.id    = vif.wr_slv_drv_cb.awid;
                aw_info.addr  = vif.wr_slv_drv_cb.awaddr;
                aw_info.len   = vif.wr_slv_drv_cb.awlen;
                aw_info.size  = vif.wr_slv_drv_cb.awsize;
                aw_info.burst = vif.wr_slv_drv_cb.awburst;
                slv_aw_q.push_back(aw_info);

                `uvm_info("WR_SLV_AW", $sformatf("Slave accepted AW: id=0x%0h, addr=0x%04h, len=%0d beats",
                          aw_info.id, aw_info.addr, aw_info.len + 1), UVM_HIGH)
            end
        end
    endtask : slave_handle_aw

    // Slave W Channel: WREADY tied HIGH, consumes write data beats until wlast
    virtual task slave_handle_w();
        vif.wr_slv_drv_cb.wready <= 1'b1;
        forever begin
            @(vif.wr_slv_drv_cb);
            if (vif.wr_slv_drv_cb.wvalid) begin
                `uvm_info("WR_SLV_W", $sformatf("Slave accepted W beat: data=0x%08h, strb=0x%01h, last=%0b",
                          vif.wr_slv_drv_cb.wdata, vif.wr_slv_drv_cb.wstrb, vif.wr_slv_drv_cb.wlast), UVM_FULL)

                if (vif.wr_slv_drv_cb.wlast) begin
                    slv_w_bursts_done++;
                end
            end
        end
    endtask : slave_handle_w

    // Slave B Channel: drives write response once AW and W bursts complete
    virtual task slave_handle_b();
        slv_aw_info_t aw_info;
        vif.wr_slv_drv_cb.bvalid <= 1'b0;
        vif.wr_slv_drv_cb.bid    <= '0;
        vif.wr_slv_drv_cb.bresp  <= '0;

        forever begin
            wait (slv_aw_q.size() > 0 && slv_w_bursts_done > 0);
            aw_info = slv_aw_q.pop_front();
            slv_w_bursts_done--;

            vif.wr_slv_drv_cb.bid    <= aw_info.id;
            vif.wr_slv_drv_cb.bresp  <= 2'b00; // AXI_RESP_OKAY
            vif.wr_slv_drv_cb.bvalid <= 1'b1;

            `uvm_info("WR_SLV_B", $sformatf("Slave asserting B response: bid=0x%0h, bresp=OKAY", aw_info.id), UVM_HIGH)

            do begin
                @(vif.wr_slv_drv_cb);
            end while (!vif.wr_slv_drv_cb.bready);

            vif.wr_slv_drv_cb.bvalid <= 1'b0;
            vif.wr_slv_drv_cb.bid    <= '0;
            vif.wr_slv_drv_cb.bresp  <= '0;
        end
    endtask : slave_handle_b

endclass : axi_wr_driver

`endif // AXI_WR_DRIVER_SV
