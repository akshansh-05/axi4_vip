// File: axi_rd_driver.sv
// Dedicated UVM Driver for AXI4 Memory-Mapped Read Channels (AR, R).

`ifndef AXI_RD_DRIVER_SV
`define AXI_RD_DRIVER_SV

class axi_rd_driver #(
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
    } slv_ar_info_t;

    slv_ar_info_t slv_ar_q[$];

    `uvm_component_param_utils(axi_rd_driver #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_rd_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("RD_DRV_CFG", "Failed to get axi_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        reset_signals();

        wait(!vif.rst);
        @(vif.rd_drv_cb);

        if (cfg.is_master) begin
            run_master();
        end else begin
            run_slave();
        end
    endtask : run_phase

    virtual task reset_master_signals();
        vif.rd_drv_cb.arid    <= '0;
        vif.rd_drv_cb.araddr  <= '0;
        vif.rd_drv_cb.arlen   <= '0;
        vif.rd_drv_cb.arsize  <= '0;
        vif.rd_drv_cb.arburst <= '0;
        vif.rd_drv_cb.arvalid <= 1'b0;

        vif.rd_drv_cb.rready  <= 1'b0;
    endtask : reset_master_signals

    virtual task reset_slave_signals();
        vif.rd_slv_drv_cb.arready <= 1'b0;

        vif.rd_slv_drv_cb.rid     <= '0;
        vif.rd_slv_drv_cb.rdata   <= '0;
        vif.rd_slv_drv_cb.rresp   <= '0;
        vif.rd_slv_drv_cb.rlast   <= 1'b0;
        vif.rd_slv_drv_cb.rvalid  <= 1'b0;
        slv_ar_q.delete();
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

            `uvm_info("RD_DRV", $sformatf("Driving transaction received from sequencer:\n%s", req.sprint()), UVM_LOW)

            drive_master_read(req);

            seq_item_port.item_done();
        end
    endtask : run_master

    virtual task drive_master_read(req_type req);
        // Step 1: Drive Read Address Channel (AR)
        repeat (req.addr_delay) @(vif.rd_drv_cb);

        vif.rd_drv_cb.arid    <= req.id;
        vif.rd_drv_cb.araddr  <= req.addr;
        vif.rd_drv_cb.arlen   <= req.len;
        vif.rd_drv_cb.arsize  <= req.size;
        vif.rd_drv_cb.arburst <= req.burst;
        vif.rd_drv_cb.arvalid <= 1'b1;

        do begin
            @(vif.rd_drv_cb);
        end while (!vif.rd_drv_cb.arready);

        vif.rd_drv_cb.arvalid <= 1'b0;

        // Step 2: Receive Read Data Channel (R) beats
        req.data  = new[req.len + 1];
        req.rresp = new[req.len + 1];
        req.rid   = new[req.len + 1];
        req.rlast = new[req.len + 1];

        vif.rd_drv_cb.rready <= 1'b1;
        for (int i = 0; i <= req.len; i++) begin
            do begin
                @(vif.rd_drv_cb);
            end while (!vif.rd_drv_cb.rvalid);

            req.data[i]  = vif.rd_drv_cb.rdata;
            req.rresp[i] = vif.rd_drv_cb.rresp;
            req.rid[i]   = vif.rd_drv_cb.rid;
            req.rlast[i] = vif.rd_drv_cb.rlast;

            `uvm_info("RD_DRV_DATA", $sformatf("DUT Read Beat [%0d/%0d]: rdata=0x%08h, rresp=2'b%0b, rid=0x%0h",
                      i, req.len, req.data[i], req.rresp[i], req.rid[i]), UVM_HIGH)
        end

        vif.rd_drv_cb.rready <= 1'b0;

        `uvm_info("RD_DRV", $sformatf("Completed Read Transaction received from DUT:\n%s", req.sprint()), UVM_LOW)
    endtask : drive_master_read

    virtual task run_slave();
        `uvm_info("RD_DRV", "AXI Slave Read mode running.", UVM_LOW)
        fork
            slave_handle_ar();
            slave_handle_r();
        join
    endtask : run_slave

    // Slave AR Channel: Controls ARREADY and models address backpressure
    virtual task slave_handle_ar();
        slv_ar_info_t ar_info;
        int unsigned  stall_cycles;

        if (!cfg.enable_arready_stall) begin
            vif.rd_slv_drv_cb.arready <= 1'b1;
            forever begin
                @(vif.rd_slv_drv_cb);
                if (vif.rd_slv_drv_cb.arvalid) begin
                    ar_info.id    = vif.rd_slv_drv_cb.arid;
                    ar_info.addr  = vif.rd_slv_drv_cb.araddr;
                    ar_info.len   = vif.rd_slv_drv_cb.arlen;
                    ar_info.size  = vif.rd_slv_drv_cb.arsize;
                    ar_info.burst = vif.rd_slv_drv_cb.arburst;
                    slv_ar_q.push_back(ar_info);

                    `uvm_info("RD_SLV_AR", $sformatf("Slave accepted AR: id=0x%0h, addr=0x%04h, len=%0d beats",
                              ar_info.id, ar_info.addr, ar_info.len + 1), UVM_LOW)
                end
            end
        end else begin
            vif.rd_slv_drv_cb.arready <= 1'b0;
            forever begin
                @(vif.rd_slv_drv_cb);
                if (vif.rd_slv_drv_cb.arvalid) begin
                    stall_cycles = $urandom_range(cfg.min_arready_delay, cfg.max_arready_delay);
                    if (stall_cycles > 0) begin
                        vif.rd_slv_drv_cb.arready <= 1'b0;
                        repeat (stall_cycles) @(vif.rd_slv_drv_cb);
                    end

                    // Assert ARREADY for 1 clock cycle to complete address handshake
                    vif.rd_slv_drv_cb.arready <= 1'b1;
                    @(vif.rd_slv_drv_cb);
                    ar_info.id    = vif.rd_slv_drv_cb.arid;
                    ar_info.addr  = vif.rd_slv_drv_cb.araddr;
                    ar_info.len   = vif.rd_slv_drv_cb.arlen;
                    ar_info.size  = vif.rd_slv_drv_cb.arsize;
                    ar_info.burst = vif.rd_slv_drv_cb.arburst;
                    slv_ar_q.push_back(ar_info);

                    `uvm_info("RD_SLV_AR", $sformatf("Slave accepted AR after %0d stall cycles: id=0x%0h, addr=0x%04h, len=%0d beats",
                              stall_cycles, ar_info.id, ar_info.addr, ar_info.len + 1), UVM_LOW)

                    vif.rd_slv_drv_cb.arready <= 1'b0;
                end
            end
        end
    endtask : slave_handle_ar

    // Slave R Channel: Drives read data beats, modeling initial latency and inter-beat bubbles
    virtual task slave_handle_r();
        slv_ar_info_t ar_info;
        bit [DATA_WIDTH-1:0] beat_data;
        int unsigned bubble_cycles;

        forever begin
            while (slv_ar_q.size() == 0) begin
                @(vif.rd_slv_drv_cb);
            end
            ar_info = slv_ar_q.pop_front();

            // Initial memory read access latency before first beat
            if (cfg.initial_rdata_delay > 0) begin
                repeat (cfg.initial_rdata_delay) @(vif.rd_slv_drv_cb);
            end

            for (int i = 0; i <= ar_info.len; i++) begin
                // Inter-beat bubbles between consecutive beats
                if (cfg.enable_r_bubbles && (i > 0)) begin
                    bubble_cycles = $urandom_range(cfg.min_r_bubble, cfg.max_r_bubble);
                    if (bubble_cycles > 0) begin
                        vif.rd_slv_drv_cb.rvalid <= 1'b0;
                        vif.rd_slv_drv_cb.rlast  <= 1'b0;
                        repeat (bubble_cycles) @(vif.rd_slv_drv_cb);
                    end
                end

                // Generate deterministic pattern: base address + beat offset
                beat_data = 32'hA000_0000 | ((ar_info.addr + (i * 4)) & 16'hFFFF);

                vif.rd_slv_drv_cb.rid    <= ar_info.id;
                vif.rd_slv_drv_cb.rdata  <= beat_data;
                vif.rd_slv_drv_cb.rresp  <= 2'b00; // AXI_RESP_OKAY
                vif.rd_slv_drv_cb.rlast  <= (i == ar_info.len);
                vif.rd_slv_drv_cb.rvalid <= 1'b1;

                `uvm_info("RD_SLV_R", $sformatf("Slave driving R beat [%0d/%0d]: data=0x%08h, last=%0b",
                          i, ar_info.len, beat_data, (i == ar_info.len)), UVM_FULL)

                @(vif.rd_slv_drv_cb);
                while (!vif.rd_slv_drv_cb.rready) begin
                    @(vif.rd_slv_drv_cb);
                end
            end

            vif.rd_slv_drv_cb.rvalid <= 1'b0;
            vif.rd_slv_drv_cb.rlast  <= 1'b0;
            vif.rd_slv_drv_cb.rdata  <= '0;
            vif.rd_slv_drv_cb.rid    <= '0;
            vif.rd_slv_drv_cb.rresp  <= '0;
        end
    endtask : slave_handle_r

endclass : axi_rd_driver

`endif // AXI_RD_DRIVER_SV
