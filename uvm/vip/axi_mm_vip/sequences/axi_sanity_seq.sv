// File: axi_sanity_seq.sv
// Sanity sequence for AXI4 Memory-Mapped bus.
// Sends a 4-beat Write burst followed by a 4-beat Read burst to address 0x1000.

`ifndef AXI_SANITY_SEQ_SV
`define AXI_SANITY_SEQ_SV

class axi_sanity_seq #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
) extends uvm_sequence #(axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH));

    typedef axi_seq_item #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) item_type;

    `uvm_object_param_utils(axi_sanity_seq #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH))

    function new(string name = "axi_sanity_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type wr_item;
        item_type rd_item;

        `uvm_info("SANITY_SEQ", "Starting AXI Sanity Sequence: 4-Beat Write followed by 4-Beat Read", UVM_LOW)

        // 1. Send 4-Beat Write Burst to Address 0x1000
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
            `uvm_fatal("SANITY_SEQ", "Randomization failed for wr_item")
        end
        `uvm_info("SANITY_SEQ", "Generated Write Transaction:", UVM_MEDIUM)
        wr_item.print();
        finish_item(wr_item);

        // 2. Send 4-Beat Read Burst from Address 0x1000
        rd_item = item_type::type_id::create("rd_item");
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
            `uvm_fatal("SANITY_SEQ", "Randomization failed for rd_item")
        end
        `uvm_info("SANITY_SEQ", "Generated Read Transaction:", UVM_MEDIUM)
        rd_item.print();
        finish_item(rd_item);

        `uvm_info("SANITY_SEQ", "AXI Sanity Sequence Completed Successfully", UVM_LOW)
    endtask : body

endclass : axi_sanity_seq

`endif // AXI_SANITY_SEQ_SV
