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

    // Channel transfer structures for decoupled concurrent capture
    typedef struct {
        bit [ID_WIDTH-1:0]    id;
        bit [ADDR_WIDTH-1:0]  addr;
        bit [7:0]             len;
        bit [2:0]             size;
        axi_burst_type_e      burst;
        time                  timestamp;
    } addr_desc_t;

    typedef struct {
        bit [DATA_WIDTH-1:0] data;
        bit [STRB_WIDTH-1:0] strb;
        bit                  last;
    } w_beat_t;

    typedef struct {
        bit [ID_WIDTH-1:0] id;
        bit [1:0]          bresp;
    } b_resp_t;

    // Internal sampling queues
    addr_desc_t aw_q[$];
    w_beat_t    w_q[$];
    b_resp_t    b_q[$];
    addr_desc_t ar_q[$];

    virtual task run_phase(uvm_phase phase);
        wait(!vif.rst);
        @(vif.mon_cb);

        fork
            collect_aw_channel();
            collect_w_channel();
            collect_b_channel();
            assemble_write_transactions();
            collect_ar_channel();
            collect_r_channel_and_assemble();
        join
    endtask : run_phase

    // Collects Write Address (AW) channel handshakes
    virtual task collect_aw_channel();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
                addr_desc_t desc;
                desc.id        = vif.mon_cb.awid;
                desc.addr      = vif.mon_cb.awaddr;
                desc.len       = vif.mon_cb.awlen;
                desc.size      = vif.mon_cb.awsize;
                desc.burst     = axi_burst_type_e'(vif.mon_cb.awburst);
                desc.timestamp = $time;
                aw_q.push_back(desc);
            end
        end
    endtask : collect_aw_channel

    // Collects Write Data (W) channel handshakes
    virtual task collect_w_channel();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.wvalid && vif.mon_cb.wready) begin
                w_beat_t beat;
                beat.data = vif.mon_cb.wdata;
                beat.strb = vif.mon_cb.wstrb;
                beat.last = vif.mon_cb.wlast;
                w_q.push_back(beat);
            end
        end
    endtask : collect_w_channel

    // Collects Write Response (B) channel handshakes
    virtual task collect_b_channel();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.bvalid && vif.mon_cb.bready) begin
                b_resp_t resp;
                resp.id    = vif.mon_cb.bid;
                resp.bresp = vif.mon_cb.bresp;
                b_q.push_back(resp);
            end
        end
    endtask : collect_b_channel

    // Assembles completed Write Transactions and broadcasts via analysis port
    virtual task assemble_write_transactions();
        forever begin
            wait(aw_q.size() > 0 && b_q.size() > 0);
            if (w_q.size() >= (aw_q[0].len + 1)) begin
                addr_desc_t desc = aw_q.pop_front();
                b_resp_t    resp = b_q.pop_front();
                item_type   write_item = item_type::type_id::create("mon_write_item");

                write_item.trans_type = AXI_WRITE;
                write_item.id         = desc.id;
                write_item.addr       = desc.addr;
                write_item.len        = desc.len;
                write_item.size       = desc.size;
                write_item.burst      = desc.burst;
                write_item.bid        = resp.id;
                write_item.bresp      = resp.bresp;

                write_item.data = new[desc.len + 1];
                write_item.strb = new[desc.len + 1];

                for (int i = 0; i <= desc.len; i++) begin
                    w_beat_t beat = w_q.pop_front();
                    write_item.data[i] = beat.data;
                    write_item.strb[i] = beat.strb;
                end

                `uvm_info("AXI_MON_WR", $sformatf("Captured WRITE Burst: addr=0x%04h, len=%0d (%0d beats), size=%0d, burst=%s, bresp=2'b%0b",
                          write_item.addr, write_item.len, write_item.len + 1, write_item.size, write_item.burst.name(), write_item.bresp), UVM_MEDIUM)

                ap.write(write_item);
            end else begin
                @(vif.mon_cb);
            end
        end
    endtask : assemble_write_transactions

    // Collects Read Address (AR) channel handshakes
    virtual task collect_ar_channel();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
                addr_desc_t desc;
                desc.id        = vif.mon_cb.arid;
                desc.addr      = vif.mon_cb.araddr;
                desc.len       = vif.mon_cb.arlen;
                desc.size      = vif.mon_cb.arsize;
                desc.burst     = axi_burst_type_e'(vif.mon_cb.arburst);
                desc.timestamp = $time;
                ar_q.push_back(desc);
            end
        end
    endtask : collect_ar_channel

    // Collects Read Data (R) channel beats and assembles completed Read Transactions
    virtual task collect_r_channel_and_assemble();
        forever begin
            wait(ar_q.size() > 0);
            begin
                addr_desc_t desc = ar_q.pop_front();
                item_type   read_item = item_type::type_id::create("mon_read_item");

                read_item.trans_type = AXI_READ;
                read_item.id         = desc.id;
                read_item.addr       = desc.addr;
                read_item.len        = desc.len;
                read_item.size       = desc.size;
                read_item.burst      = desc.burst;

                read_item.data  = new[desc.len + 1];
                read_item.rresp = new[desc.len + 1];
                read_item.rid   = new[desc.len + 1];

                for (int i = 0; i <= desc.len; i++) begin
                    do begin
                        @(vif.mon_cb);
                    end while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));

                    read_item.data[i]  = vif.mon_cb.rdata;
                    read_item.rresp[i] = vif.mon_cb.rresp;
                    read_item.rid[i]   = vif.mon_cb.rid;
                end

                `uvm_info("AXI_MON_RD", $sformatf("Captured READ Burst: addr=0x%04h, len=%0d (%0d beats), size=%0d, burst=%s, rdata[0]=0x%08h",
                          read_item.addr, read_item.len, read_item.len + 1, read_item.size, read_item.burst.name(), read_item.data[0]), UVM_MEDIUM)

                ap.write(read_item);
            end
        end
    endtask : collect_r_channel_and_assemble

endclass : axi_monitor

`endif // AXI_MONITOR_SV
