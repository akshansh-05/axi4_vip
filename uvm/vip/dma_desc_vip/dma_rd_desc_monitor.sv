// File: dma_rd_desc_monitor.sv
// Description: UVM Monitor for the Read Descriptor interface. Operates in two phases:
//              1. process_cmd(): Samples accepted descriptor commands (read_desc_valid && ready),
//                 stores them in pending_cmds by tag, and publishes to cmd_ap for scoreboard tracking.
//              2. process_status(): Samples completion pulses (read_desc_status_valid), retrieves
//                 and retires the matching in-flight command, stamps the status error code, and
//                 publishes the completed descriptor to status_ap.
//              Evaluates status before command on each clock edge to safely retire completed tags
//              prior to immediate tag reuse by a new command on the same cycle.

`ifndef DMA_RD_DESC_MONITOR_SV
`define DMA_RD_DESC_MONITOR_SV

class dma_rd_desc_monitor #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_monitor;

    // Typedefs for sequence item and agent configuration
    typedef dma_desc_seq_item     #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;
    typedef dma_desc_agent_config #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) cfg_type;

    // Virtual interface handle to read descriptor physical signals
    virtual dma_desc_if #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) vif;
    cfg_type cfg;

    // Analysis ports: cmd_ap for new commands, status_ap for completion status
    uvm_analysis_port #(item_type) cmd_ap;
    uvm_analysis_port #(item_type) status_ap;

    `uvm_component_param_utils(dma_rd_desc_monitor #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Constructor creating the two analysis ports
    function new(string name = "dma_rd_desc_monitor", uvm_component parent = null);
        super.new(name, parent);
        cmd_ap    = new("cmd_ap", this);
        status_ap = new("status_ap", this);
    endfunction : new

    // Retrieve agent configuration and interface handle from config DB
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cfg_type)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("RD_DESC_MON_CFG", "Failed to get dma_desc_agent_config from config_db")
        end
        vif = cfg.vif;
    endfunction : build_phase

    // Associative array tracking in-flight commands indexed by descriptor tag
    item_type pending_cmds[bit [TAG_WIDTH-1:0]];

    virtual task run_phase(uvm_phase phase);
        forever begin
            // Wait for reset deassertion before monitoring interface activity
            wait(!vif.rst);
            while (!vif.rst) begin
                // Synchronize sampling to the monitor clocking block edge
                @(vif.rd_desc_mon_cb);
                if (!vif.rst) begin
                    // Priority: Process status before command on the same cycle.
                    // This frees the tag first if a new command reuses it on the same clock edge.
                    if (vif.rd_desc_mon_cb.read_desc_status_valid) begin
                        process_status();
                    end
                    // Sample command only when both valid and ready handshake signals are asserted
                    if (vif.rd_desc_mon_cb.read_desc_valid &&
                        vif.rd_desc_mon_cb.read_desc_ready) begin
                        process_cmd();
                    end
                end
            end
            // Flush pending commands if reset is asserted mid-test
            pending_cmds.delete();
        end
    endtask : run_phase

    // Passively samples read descriptor command handshakes (valid && ready)
    virtual function void process_cmd();
        item_type item;
        item_type cmd_snapshot;

        // Instantiate new transaction item to hold sampled command fields
        item = item_type::type_id::create("rd_desc_cmd_item");
        item.trans_type = DESC_READ;
        item.addr       = vif.rd_desc_mon_cb.read_desc_addr; // Read starting address
        item.len        = vif.rd_desc_mon_cb.read_desc_len;  // Transfer byte length
        item.tag        = vif.rd_desc_mon_cb.read_desc_tag;  // Tag for matching completion status
        item.id         = vif.rd_desc_mon_cb.read_desc_id;   // Stream TID metadata
        item.dest       = vif.rd_desc_mon_cb.read_desc_dest; // Stream TDEST routing tag
        item.user       = vif.rd_desc_mon_cb.read_desc_user; // Stream TUSER sideband

        `uvm_info("RD_DESC_MON", $sformatf("Sampled Read Descriptor Command:\n%s", item.sprint()), UVM_LOW)

        // Check for illegal tag collisions with commands already in-flight
        if (pending_cmds.exists(item.tag)) begin
            `uvm_error("RD_DESC_MON", $sformatf("Duplicate outstanding command tag detected: tag=0x%02x is already pending!", item.tag))
        end else begin
            // Save command in associative array until status returns
            pending_cmds[item.tag] = item;
        end

        // Deep-copy item before broadcasting to protect scoreboard from downstream mutation
        if (!$cast(cmd_snapshot, item.clone())) begin
            `uvm_fatal("RD_DESC_MON", "Failed to clone read descriptor command item")
        end else if (cmd_snapshot == null) begin
            `uvm_fatal("RD_DESC_MON", "Clone returned a null read descriptor command item")
        end else begin
            // Broadcast cloned command to scoreboard via cmd_ap
            cmd_ap.write(cmd_snapshot);
        end
    endfunction : process_cmd

    // Passively samples read descriptor completion status pulses (status_valid)
    virtual function void process_status();
        bit [TAG_WIDTH-1:0] s_tag;
        item_type item;

        // Read completion tag from interface
        s_tag = vif.rd_desc_mon_cb.read_desc_status_tag;

        // Retrieve the corresponding in-flight command for this tag
        if (pending_cmds.exists(s_tag)) begin
            item = pending_cmds[s_tag];
            // Remove completed command from pending tracking table
            pending_cmds.delete(s_tag);
        end else begin
            // Protocol violation: status received without an active pending command
            `uvm_error("RD_DESC_MON", $sformatf("Received status for tag 0x%02x with no matching pending command!", s_tag))
            item = item_type::type_id::create("rd_desc_status_item");
            item.trans_type = DESC_READ;
            item.tag        = s_tag;
        end

        // Populate completion status response fields
        item.status_tag   = s_tag;
        item.status_error = dma_error_e'(vif.rd_desc_mon_cb.read_desc_status_error); // Error code (0 = OKAY)

        `uvm_info("RD_DESC_MON", $sformatf("Sampled Read Descriptor Status:\n%s", item.sprint()), UVM_LOW)

        // Broadcast status transaction to scoreboard via status_ap
        status_ap.write(item);
    endfunction : process_status

endclass : dma_rd_desc_monitor

`endif // DMA_RD_DESC_MONITOR_SV
