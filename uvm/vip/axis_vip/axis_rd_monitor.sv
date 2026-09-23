// File: axis_rd_monitor.sv
// Description: UVM Monitor for AXI4-Stream Read Channel. Passively snoops
//              the m_axis_read_data_* interface, reconstructs completed stream
//              packets, and publishes them via an analysis port.

`ifndef AXIS_RD_MONITOR_SV
`define AXIS_RD_MONITOR_SV

class axis_rd_monitor #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_monitor;

    typedef axis_seq_item     #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;
    typedef axis_agent_config #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) cfg_type;

    virtual axis_if #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) vif;
    cfg_type cfg;

    uvm_analysis_port #(item_type) ap;

    `uvm_component_param_utils(axis_rd_monitor #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "axis_rd_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("AXIS_RD_MON_CFG", "Failed to get axis_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        wait(!vif.rst);
        @(vif.mon_cb);

        forever begin
            collect_packet();
        end
    endtask : run_phase

    // Snoop handshakes on the read stream interface and reconstruct
    // a complete packet when TLAST is observed
    virtual task collect_packet();
        item_type item;
        bit [DATA_WIDTH-1:0] data_q[$];
        bit [KEEP_WIDTH-1:0] keep_q[$];
        bit [USER_WIDTH-1:0] user_q[$];
        bit [ID_WIDTH-1:0]   captured_id;
        bit [DEST_WIDTH-1:0] captured_dest;
        bit                  got_last;

        got_last = 1'b0;

        while (!got_last) begin
            @(vif.mon_cb);

            // Only sample on a valid handshake (TVALID && TREADY) outside reset
            if (vif.mon_cb.tvalid && vif.mon_cb.tready && !vif.rst) begin
                data_q.push_back(vif.mon_cb.tdata);
                keep_q.push_back(vif.mon_cb.tkeep);
                user_q.push_back(vif.mon_cb.tuser);
                captured_id   = vif.mon_cb.tid;
                captured_dest = vif.mon_cb.tdest;

                if (vif.mon_cb.tlast) begin
                    got_last = 1'b1;
                end
            end
        end

        // Build the sequence item from collected beats
        item = item_type::type_id::create("axis_rd_mon_item");
        item.data = new[data_q.size()];
        item.keep = new[keep_q.size()];
        item.user = new[user_q.size()];

        foreach (data_q[i]) begin
            item.data[i] = data_q[i];
            item.keep[i] = keep_q[i];
            item.user[i] = user_q[i];
        end

        item.id   = captured_id;
        item.dest = captured_dest;
        item.last = 1'b1;

        `uvm_info(get_type_name(), $sformatf("Collected read stream packet: %0d beats, ID=0x%0x, DEST=0x%0x",
                  item.data.size(), item.id, item.dest), UVM_HIGH)

        ap.write(item);
    endtask : collect_packet

endclass : axis_rd_monitor

`endif // AXIS_RD_MONITOR_SV
