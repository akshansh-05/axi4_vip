// File: axis_slave_rx_seq.sv
// Description: Slave sequence for AXI4-Stream VIP. Sends response items to
//              axis_rd_driver to control TREADY assertion and backpressure delays.

`ifndef AXIS_SLAVE_RX_SEQ_SV
`define AXIS_SLAVE_RX_SEQ_SV

class axis_slave_rx_seq #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends axis_base_seq #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH);

    typedef axis_seq_item #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(axis_slave_rx_seq #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable backpressure delay per beat (0 = immediate ready, >0 = stall cycles)
    rand int unsigned ready_delay;

    // Number of beats to accept (0 = run forever in background)
    int unsigned num_beats = 0;

    constraint c_default_ready_delay {
        soft ready_delay inside {[0:5]};
    }

    function new(string name = "axis_slave_rx_seq");
        super.new(name);
        ready_delay = 0;
    endfunction : new

    virtual task body();
        item_type req;

        if (num_beats == 0) begin
            // Run forever in background
            forever begin
                `uvm_create(req)
                if (!req.randomize() with { req.ready_delay == local::ready_delay; }) begin
                    `uvm_error("AXIS_SLV_SEQ", "Randomization failed for axis_seq_item")
                end
                `uvm_send(req)
            end
        end else begin
            // Accept a fixed number of beats
            repeat (num_beats) begin
                `uvm_create(req)
                if (!req.randomize() with { req.ready_delay == local::ready_delay; }) begin
                    `uvm_error("AXIS_SLV_SEQ", "Randomization failed for axis_seq_item")
                end
                `uvm_send(req)
            end
        end
    endtask : body

endclass : axis_slave_rx_seq

`endif // AXIS_SLAVE_RX_SEQ_SV
