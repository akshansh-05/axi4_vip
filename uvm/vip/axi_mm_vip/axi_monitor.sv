// File: axi_monitor.sv
// UVM Monitor for AXI4 Memory-Mapped bus.
// Passively snoops AW, W, B, AR, and R channels, reconstructs complete burst transactions,
// and broadcasts them via analysis port to scoreboards and coverage collectors.

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
        @(posedge vif.clk);

        fork
            monitor_write_channel();
            monitor_read_channel();
        join
    endtask : run_phase

    // Observes Write Address (AW), Write Data (W), and Write Response (B)
    virtual task monitor_write_channel();
        forever begin
            item_type write_item;
            write_item = item_type::type_id::create("mon_write_item");
            write_item.trans_type = AXI_WRITE;

            // 1. Capture Write Address Phase (AW)
            do begin
                @(posedge vif.clk);
            end while (!(vif.awvalid && vif.awready));

            write_item.id    = vif.awid;
            write_item.addr  = vif.awaddr;
            write_item.len   = vif.awlen;
            write_item.size  = vif.awsize;
            write_item.burst = axi_burst_type_e'(vif.awburst);

            write_item.data = new[write_item.len + 1];
            write_item.strb = new[write_item.len + 1];

            // 2. Capture Write Data Phase (W) beats
            for (int i = 0; i <= write_item.len; i++) begin
                do begin
                    @(posedge vif.clk);
                end while (!(vif.wvalid && vif.wready));

                write_item.data[i] = vif.wdata;
                write_item.strb[i] = vif.wstrb;
            end

            // 3. Capture Write Response Phase (B)
            do begin
                @(posedge vif.clk);
            end while (!(vif.bvalid && vif.bready));

            write_item.bid   = vif.bid;
            write_item.bresp = vif.bresp;

            // Broadcast completed write transaction to scoreboard & coverage
            ap.write(write_item);
        end
    endtask : monitor_write_channel

    // Observes Read Address (AR) and Read Data (R)
    virtual task monitor_read_channel();
        forever begin
            item_type read_item;
            read_item = item_type::type_id::create("mon_read_item");
            read_item.trans_type = AXI_READ;

            // 1. Capture Read Address Phase (AR)
            do begin
                @(posedge vif.clk);
            end while (!(vif.arvalid && vif.arready));

            read_item.id    = vif.arid;
            read_item.addr  = vif.araddr;
            read_item.len   = vif.arlen;
            read_item.size  = vif.arsize;
            read_item.burst = axi_burst_type_e'(vif.arburst);

            read_item.data  = new[read_item.len + 1];
            read_item.rresp = new[read_item.len + 1];
            read_item.rid   = new[read_item.len + 1];

            // 2. Capture Read Data Phase (R) beats
            for (int i = 0; i <= read_item.len; i++) begin
                do begin
                    @(posedge vif.clk);
                end while (!(vif.rvalid && vif.rready));

                read_item.data[i]  = vif.rdata;
                read_item.rresp[i] = vif.rresp;
                read_item.rid[i]   = vif.rid;
            end

            // Broadcast completed read transaction to scoreboard & coverage
            ap.write(read_item);
        end
    endtask : monitor_read_channel

endclass : axi_monitor

`endif // AXI_MONITOR_SV
