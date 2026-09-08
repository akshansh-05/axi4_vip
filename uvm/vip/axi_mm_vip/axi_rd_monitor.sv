// File: axi_rd_monitor.sv
// Dedicated UVM Monitor for AXI4 Memory-Mapped Read Channels (AR, R).
// Passively snoops AR and R channels strictly through rd_mon_cb clocking block,
// reconstructs complete burst transactions, and broadcasts them via analysis port.

`ifndef AXI_RD_MONITOR_SV
`define AXI_RD_MONITOR_SV

class axi_rd_monitor #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_monitor;

    typedef axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) item_type;

    virtual axi_if #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) vif;
    axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) cfg;

    uvm_analysis_port #(item_type) ap;

    `uvm_component_param_utils(axi_rd_monitor #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_rd_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_agent_config #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("RD_MON_CFG", "Failed to get axi_agent_config from config_db")
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

    addr_desc_t ar_q[$];

    virtual task run_phase(uvm_phase phase);
        wait(!vif.rst);
        @(vif.rd_mon_cb);

        fork
            collect_ar_channel();
            collect_r_channel_and_assemble();
        join
    endtask : run_phase

    virtual task collect_ar_channel();
        forever begin
            @(vif.rd_mon_cb);
            if (vif.rd_mon_cb.arvalid && vif.rd_mon_cb.arready) begin
                addr_desc_t desc;
                desc.id        = vif.rd_mon_cb.arid;
                desc.addr      = vif.rd_mon_cb.araddr;
                desc.len       = vif.rd_mon_cb.arlen;
                desc.size      = vif.rd_mon_cb.arsize;
                desc.burst     = axi_burst_type_e'(vif.rd_mon_cb.arburst);
                desc.timestamp = $time;
                ar_q.push_back(desc);
            end
        end
    endtask : collect_ar_channel

    virtual task collect_r_channel_and_assemble();
        item_type txn;
        addr_desc_t desc;
        int beat_idx;

        forever begin
            wait (ar_q.size() > 0);
            desc = ar_q.pop_front();

            txn = item_type::type_id::create("mon_rd_txn");
            txn.trans_type = AXI_READ;
            txn.id         = desc.id;
            txn.addr       = desc.addr;
            txn.len        = desc.len;
            txn.size       = desc.size;
            txn.burst      = desc.burst;

            txn.data  = new[desc.len + 1];
            txn.rresp = new[desc.len + 1];
            txn.rid   = new[desc.len + 1];

            beat_idx = 0;
            while (beat_idx <= desc.len) begin
                @(vif.rd_mon_cb);
                if (vif.rd_mon_cb.rvalid && vif.rd_mon_cb.rready) begin
                    txn.data[beat_idx]  = vif.rd_mon_cb.rdata;
                    txn.rresp[beat_idx] = vif.rd_mon_cb.rresp;
                    txn.rid[beat_idx]   = vif.rd_mon_cb.rid;

                    if (vif.rd_mon_cb.rlast && (beat_idx != desc.len)) begin
                        `uvm_error("RD_MON", $sformatf("Premature RLAST at beat %0d of %0d beats",
                                   beat_idx, desc.len + 1))
                    end
                    beat_idx++;
                end
            end

            `uvm_info("RD_MON", $sformatf("[READ COMPLETE] id=0x%0h addr=0x%04h len=%0d beats",
                      txn.id, txn.addr, txn.len + 1), UVM_LOW)

            ap.write(txn);
        end
    endtask : collect_r_channel_and_assemble

endclass : axi_rd_monitor

`endif // AXI_RD_MONITOR_SV
