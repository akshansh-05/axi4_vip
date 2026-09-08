// File: axi_sanity_seq.sv
// Dedicated Sanity sequences for AXI Write and Read agents.

`ifndef AXI_SANITY_SEQ_SV
`define AXI_SANITY_SEQ_SV

// Write Sanity Sequence (Runs on axi_wr_agent.seqr)
class axi_wr_sanity_seq #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_sequence #(axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH));

    typedef axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) item_type;

    `uvm_object_param_utils(axi_wr_sanity_seq #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_wr_sanity_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type wr_item;

        `uvm_info("WR_SANITY_SEQ", "Starting AXI Write Sanity Sequence: 4-Beat Write to 0x1000", UVM_LOW)

        wr_item = item_type::type_id::create("wr_item");
        start_item(wr_item);
        if (!wr_item.randomize() with {
            trans_type == AXI_WRITE;
            id         == 8'h01;
            addr       == 16'h1000;
            len        == 8'd3;            // 4 beats
            size       == 3'd2;            // 4 bytes per beat
            burst      == AXI_BURST_INCR;  // Incrementing burst
            addr_delay == 0;
            foreach (data_delay[i]) {
                data_delay[i] == 0;
            }
        }) begin
            `uvm_fatal("WR_SANITY_SEQ", "Randomization failed for wr_item")
        end

        `uvm_info("WR_SANITY_SEQ", $sformatf("Generated Write Transaction:\n%s", wr_item.sprint()), UVM_LOW)
        finish_item(wr_item);
        `uvm_info("WR_SANITY_SEQ", "AXI Write Sanity Sequence Completed", UVM_LOW)
    endtask

endclass : axi_wr_sanity_seq


// Read Sanity Sequence (Runs on axi_rd_agent.seqr)
class axi_rd_sanity_seq #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_sequence #(axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH));

    typedef axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) item_type;

    `uvm_object_param_utils(axi_rd_sanity_seq #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_rd_sanity_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type rd_item;

        `uvm_info("RD_SANITY_SEQ", "Starting AXI Read Sanity Sequence: 4-Beat Read from 0x1000", UVM_LOW)

        rd_item = item_type::type_id::create("rd_item");
        rd_item.data.rand_mode(0);
        rd_item.strb.rand_mode(0);
        start_item(rd_item);
        if (!rd_item.randomize() with {
            trans_type == AXI_READ;
            id         == 8'h01;
            addr       == 16'h1000;
            len        == 8'd3;            // 4 beats
            size       == 3'd2;            // 4 bytes per beat
            burst      == AXI_BURST_INCR;
            addr_delay == 0;
        }) begin
            `uvm_fatal("RD_SANITY_SEQ", "Randomization failed for rd_item")
        end

        `uvm_info("RD_SANITY_SEQ", $sformatf("Generated Read Transaction:\n%s", rd_item.sprint()), UVM_LOW)
        finish_item(rd_item);
        `uvm_info("RD_SANITY_SEQ", "AXI Read Sanity Sequence Completed", UVM_LOW)
    endtask

endclass : axi_rd_sanity_seq

`endif // AXI_SANITY_SEQ_SV
