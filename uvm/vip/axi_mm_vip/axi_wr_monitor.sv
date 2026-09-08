// File: axi_wr_monitor.sv
// Dedicated UVM Monitor for AXI4 Memory-Mapped Write Channels (AW, W, B).
// Passively snoops AW, W, and B channels strictly through wr_mon_cb clocking block,
// reconstructs complete burst transactions, and broadcasts them via analysis port.

`ifndef AXI_WR_MONITOR_SV
`define AXI_WR_MONITOR_SV

class axi_wr_monitor #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_monitor;

    typedef axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) item_type;

    virtual axi_if #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) vif;
    axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) cfg;

    uvm_analysis_port #(item_type) ap;

    `uvm_component_param_utils(axi_wr_monitor #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_wr_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("WR_MON_CFG", "Failed to get axi_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

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

    addr_desc_t aw_q[$];
    w_beat_t    w_q[$];
    b_resp_t    b_q[$];

    virtual task run_phase(uvm_phase phase);
        wait(!vif.rst);
        @(vif.wr_mon_cb);

        fork
            collect_aw_channel();
            collect_w_channel();
            collect_b_channel();
            assemble_write_transactions();
        join
    endtask : run_phase

    virtual task collect_aw_channel();
        forever begin
            @(vif.wr_mon_cb);
            if (vif.wr_mon_cb.awvalid && vif.wr_mon_cb.awready) begin
                addr_desc_t desc;
                desc.id        = vif.wr_mon_cb.awid;
                desc.addr      = vif.wr_mon_cb.awaddr;
                desc.len       = vif.wr_mon_cb.awlen;
                desc.size      = vif.wr_mon_cb.awsize;
                desc.burst     = axi_burst_type_e'(vif.wr_mon_cb.awburst);
                desc.timestamp = $time;
                aw_q.push_back(desc);
            end
        end
    endtask : collect_aw_channel

    virtual task collect_w_channel();
        forever begin
            @(vif.wr_mon_cb);
            if (vif.wr_mon_cb.wvalid && vif.wr_mon_cb.wready) begin
                w_beat_t beat;
                beat.data = vif.wr_mon_cb.wdata;
                beat.strb = vif.wr_mon_cb.wstrb;
                beat.last = vif.wr_mon_cb.wlast;
                w_q.push_back(beat);
            end
        end
    endtask : collect_w_channel

    virtual task collect_b_channel();
        forever begin
            @(vif.wr_mon_cb);
            if (vif.wr_mon_cb.bvalid && vif.wr_mon_cb.bready) begin
                b_resp_t resp;
                resp.id    = vif.wr_mon_cb.bid;
                resp.bresp = vif.wr_mon_cb.bresp;
                b_q.push_back(resp);
            end
        end
    endtask : collect_b_channel

    virtual task assemble_write_transactions();
        item_type txn;
        addr_desc_t desc;
        b_resp_t    resp;

        forever begin
            wait (aw_q.size() > 0);
            desc = aw_q.pop_front();

            txn = item_type::type_id::create("mon_wr_txn");
            txn.trans_type = AXI_WRITE;
            txn.id         = desc.id;
            txn.addr       = desc.addr;
            txn.len        = desc.len;
            txn.size       = desc.size;
            txn.burst      = desc.burst;

            txn.data = new[desc.len + 1];
            txn.strb = new[desc.len + 1];

            for (int i = 0; i <= desc.len; i++) begin
                wait (w_q.size() > 0);
                begin
                    w_beat_t beat = w_q.pop_front();
                    txn.data[i] = beat.data;
                    txn.strb[i] = beat.strb;
                end
            end

            wait (b_q.size() > 0);
            resp = b_q.pop_front();
            txn.bid   = resp.id;
            txn.bresp = resp.bresp;

            `uvm_info("WR_MON", $sformatf("[WRITE COMPLETE] id=0x%0h addr=0x%04h len=%0d beats bresp=2'b%0b",
                      txn.id, txn.addr, txn.len + 1, txn.bresp), UVM_LOW)

            ap.write(txn);
        end
    endtask : assemble_write_transactions

endclass : axi_wr_monitor

`endif // AXI_WR_MONITOR_SV
