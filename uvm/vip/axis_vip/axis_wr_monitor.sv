// File: axis_wr_monitor.sv
// Description: UVM Monitor for AXI4-Stream Write Channel. Passively snoops
//              the s_axis_write_data_* interface, reconstructs completed stream
//              packets, and publishes them via an analysis port.

`ifndef AXIS_WR_MONITOR_SV
`define AXIS_WR_MONITOR_SV

class axis_wr_monitor #(
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

    `uvm_component_param_utils(axis_wr_monitor #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "axis_wr_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("AXIS_WR_MON_CFG", "Failed to get axis_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        forever begin
            wait(!vif.rst);
            @(vif.mon_cb);
            while (!vif.rst) begin
                collect_packet();
            end
        end
    endtask : run_phase

    // Snoop handshakes on the write stream interface and reconstruct
    // a complete packet when TLAST is observed
    virtual task collect_packet();
        item_type item;
        bit [DATA_WIDTH-1:0] data_q[$];
        bit [KEEP_WIDTH-1:0] keep_q[$];
        bit [USER_WIDTH-1:0] user_q[$];
        int unsigned         delay_q[$];
        bit [ID_WIDTH-1:0]   captured_id;
        bit [DEST_WIDTH-1:0] captured_dest;
        bit                  got_last;
        int unsigned         cur_delay;
        int unsigned         stall_cycles;

        got_last     = 1'b0;
        cur_delay    = 0;
        stall_cycles = 0;

        while (!got_last && !vif.rst) begin
            @(vif.mon_cb);
            if (vif.rst) break;

            // Count DUT backpressure on ingress stream: driver has valid data, but DUT holds TREADY low
            if (vif.mon_cb.tvalid && !vif.mon_cb.tready) begin
                stall_cycles++;
            end

            // Accepted beat handshake (TVALID && TREADY)
            if (vif.mon_cb.tvalid && vif.mon_cb.tready) begin
                data_q.push_back(vif.mon_cb.tdata);
                keep_q.push_back(vif.mon_cb.tkeep);
                user_q.push_back(vif.mon_cb.tuser);
                captured_id   = vif.mon_cb.tid;
                captured_dest = vif.mon_cb.tdest;

                // Record inter-beat bubble cycles (idle cycles before this beat)
                if (data_q.size() == 1) begin
                    delay_q.push_back(0); // First beat of packet
                end else begin
                    delay_q.push_back(cur_delay);
                end
                cur_delay = 0;

                if (vif.mon_cb.tlast) begin
                    got_last = 1'b1;
                end
            end else if (data_q.size() > 0 && !vif.mon_cb.tvalid) begin
                // In-progress packet bubble: Producer deasserts TVALID between beats
                cur_delay++;
            end
        end

        // Discard incomplete packet if interrupted by reset
        if (vif.rst || !got_last) begin
            return;
        end

        // Build the sequence item from collected beats
        item = item_type::type_id::create("axis_wr_mon_item");
        item.data        = new[data_q.size()];
        item.keep        = new[keep_q.size()];
        item.user        = new[user_q.size()];
        item.delay       = new[delay_q.size()];
        item.ready_delay = stall_cycles;

        foreach (data_q[i]) begin
            item.data[i]  = data_q[i];
            item.keep[i]  = keep_q[i];
            item.user[i]  = user_q[i];
            item.delay[i] = delay_q[i];
        end

        item.id   = captured_id;
        item.dest = captured_dest;

        `uvm_info(get_type_name(), $sformatf("Collected write stream packet: %0d beats, ID=0x%0x, DEST=0x%0x, stalls=%0d",
                  item.data.size(), item.id, item.dest, item.ready_delay), UVM_HIGH)

        ap.write(item);
    endtask : collect_packet

endclass : axis_wr_monitor

`endif // AXIS_WR_MONITOR_SV
