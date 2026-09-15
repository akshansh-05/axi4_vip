// File: dma_wr_desc_monitor.sv
// Description: UVM Monitor for Write Descriptor Channel. Passively snoops
//              write descriptor commands and status completions, publishing
//              reconstructed transactions via analysis port.

`ifndef DMA_WR_DESC_MONITOR_SV
`define DMA_WR_DESC_MONITOR_SV

class dma_wr_desc_monitor #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_monitor;

    typedef dma_desc_seq_item     #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;
    typedef dma_desc_agent_config #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) cfg_type;

    virtual dma_desc_if #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) vif;
    cfg_type cfg;

    uvm_analysis_port #(item_type) cmd_ap;
    uvm_analysis_port #(item_type) status_ap;

    `uvm_component_param_utils(dma_wr_desc_monitor #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    function new(string name = "dma_wr_desc_monitor", uvm_component parent = null);
        super.new(name, parent);
        cmd_ap    = new("cmd_ap", this);
        status_ap = new("status_ap", this);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("WR_DESC_MON_CFG", "Failed to get dma_desc_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    item_type pending_cmds[bit [TAG_WIDTH-1:0]];

    virtual task run_phase(uvm_phase phase);
        forever begin
            wait(!vif.rst);
            fork
                monitor_cmd();
                monitor_status();
            join_none
            wait(vif.rst);
            disable fork;
            pending_cmds.delete();
        end
    endtask : run_phase

    // Passively samples write descriptor command handshakes (valid && ready)
    virtual task monitor_cmd();
        forever begin
            @(vif.wr_desc_mon_cb);
            if (vif.wr_desc_mon_cb.write_desc_valid && vif.wr_desc_mon_cb.write_desc_ready) begin
                item_type item = item_type::type_id::create("wr_desc_cmd_item");
                item.trans_type = DESC_WRITE;
                item.addr       = vif.wr_desc_mon_cb.write_desc_addr;
                item.len        = vif.wr_desc_mon_cb.write_desc_len;
                item.tag        = vif.wr_desc_mon_cb.write_desc_tag;

                `uvm_info("WR_DESC_MON", $sformatf("Sampled Write Descriptor Command:\n%s", item.sprint()), UVM_MEDIUM)
                pending_cmds[item.tag] = item;
                cmd_ap.write(item);
            end
        end
    endtask : monitor_cmd

    // Passively samples write descriptor completion status pulses (status_valid)
    virtual task monitor_status();
        forever begin
            @(vif.wr_desc_mon_cb);
            if (vif.wr_desc_mon_cb.write_desc_status_valid) begin
                bit [TAG_WIDTH-1:0] s_tag = vif.wr_desc_mon_cb.write_desc_status_tag;
                item_type item;
                if (pending_cmds.exists(s_tag)) begin
                    item = pending_cmds[s_tag];
                    pending_cmds.delete(s_tag);
                end else begin
                    item = item_type::type_id::create("wr_desc_status_item");
                    item.trans_type = DESC_WRITE;
                    item.tag        = s_tag;
                end
                item.status_tag   = s_tag;
                item.status_len   = vif.wr_desc_mon_cb.write_desc_status_len;
                item.status_id    = vif.wr_desc_mon_cb.write_desc_status_id;
                item.status_dest  = vif.wr_desc_mon_cb.write_desc_status_dest;
                item.status_user  = vif.wr_desc_mon_cb.write_desc_status_user;
                item.status_error = dma_error_e'(vif.wr_desc_mon_cb.write_desc_status_error);

                `uvm_info("WR_DESC_MON", $sformatf("Sampled Write Descriptor Status: tag=0x%02x, len=%0d, error=%s (0x%0x)",
                          item.status_tag, item.status_len, item.status_error.name(), item.status_error), UVM_MEDIUM)
                status_ap.write(item);
            end
        end
    endtask : monitor_status

endclass : dma_wr_desc_monitor

`endif // DMA_WR_DESC_MONITOR_SV
