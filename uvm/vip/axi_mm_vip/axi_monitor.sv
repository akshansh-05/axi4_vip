// File: axi_monitor.sv
// UVM Monitor for AXI4 Memory-Mapped bus.
// Passively snoops AW, W, B, AR, and R channels strictly through mon_cb clocking block,
// reconstructs complete burst transactions, prints summary to console, and broadcasts them via analysis port.

`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV

class axi_monitor #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_monitor;

    typedef axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) item_type;

    virtual axi_if #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) vif;
    axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) cfg;

    uvm_analysis_port #(item_type) ap;

    `uvm_component_param_utils(axi_monitor #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("MON_CFG", "Failed to get axi_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        wait(!vif.rst);
        @(vif.mon_cb);

        fork
            monitor_write_channel();
            monitor_read_channel();
        join
    endtask : run_phase

    // Observes Write Address (AW), Write Data (W), and Write Response (B) strictly through mon_cb
    virtual task monitor_write_channel();
        forever begin
            item_type write_item;
            write_item = item_type::type_id::create("mon_write_item");
            write_item.trans_type = AXI_WRITE;

            // 1. Capture Write Address Phase (AW)
            do begin
                @(vif.mon_cb);
            end while (!(vif.mon_cb.awvalid && vif.mon_cb.awready));

            write_item.id    = vif.mon_cb.awid;
            write_item.addr  = vif.mon_cb.awaddr;
            write_item.len   = vif.mon_cb.awlen;
            write_item.size  = vif.mon_cb.awsize;
            write_item.burst = axi_burst_type_e'(vif.mon_cb.awburst);

            write_item.data = new[write_item.len + 1];
            write_item.strb = new[write_item.len + 1];

            // 2. Capture Write Data Phase (W) beats
            for (int i = 0; i <= write_item.len; i++) begin
                do begin
                    @(vif.mon_cb);
                end while (!(vif.mon_cb.wvalid && vif.mon_cb.wready));

                write_item.data[i] = vif.mon_cb.wdata;
                write_item.strb[i] = vif.mon_cb.wstrb;
            end

            // 3. Capture Write Response Phase (B)
            do begin
                @(vif.mon_cb);
            end while (!(vif.mon_cb.bvalid && vif.mon_cb.bready));

            write_item.bid   = vif.mon_cb.bid;
            write_item.bresp = vif.mon_cb.bresp;

            `uvm_info("AXI_MON_WR", $sformatf("Captured WRITE Burst: addr=0x%04h, len=%0d (%0d beats), size=%0d, burst=%s, bresp=2'b%0b",
                      write_item.addr, write_item.len, write_item.len + 1, write_item.size, write_item.burst.name(), write_item.bresp), UVM_MEDIUM)

            // Broadcast completed write transaction to subscribers
            ap.write(write_item);
        end
    endtask : monitor_write_channel

    // Observes Read Address (AR) and Read Data (R) strictly through mon_cb
    virtual task monitor_read_channel();
        forever begin
            item_type read_item;
            read_item = item_type::type_id::create("mon_read_item");
            read_item.trans_type = AXI_READ;

            // 1. Capture Read Address Phase (AR)
            do begin
                @(vif.mon_cb);
            end while (!(vif.mon_cb.arvalid && vif.mon_cb.arready));

            read_item.id    = vif.mon_cb.arid;
            read_item.addr  = vif.mon_cb.araddr;
            read_item.len   = vif.mon_cb.arlen;
            read_item.size  = vif.mon_cb.arsize;
            read_item.burst = axi_burst_type_e'(vif.mon_cb.arburst);

            read_item.data  = new[read_item.len + 1];
            read_item.rresp = new[read_item.len + 1];
            read_item.rid   = new[read_item.len + 1];

            // 2. Capture Read Data Phase (R) beats
            for (int i = 0; i <= read_item.len; i++) begin
                do begin
                    @(vif.mon_cb);
                end while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));

                read_item.data[i]  = vif.mon_cb.rdata;
                read_item.rresp[i] = vif.mon_cb.rresp;
                read_item.rid[i]   = vif.mon_cb.rid;
            end

            `uvm_info("AXI_MON_RD", $sformatf("Captured READ Burst: addr=0x%04h, len=%0d (%0d beats), size=%0d, burst=%s, rdata[0]=0x%08h",
                      read_item.addr, read_item.len, read_item.len + 1, read_item.size, read_item.burst.name(), read_item.data[0]), UVM_MEDIUM)

            // Broadcast completed read transaction to subscribers
            ap.write(read_item);
        end
    endtask : monitor_read_channel

endclass : axi_monitor

`endif // AXI_MONITOR_SV
