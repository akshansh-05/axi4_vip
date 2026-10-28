// File: axis_rd_backpressure_seq.sv
// Description: Reactive slave sequence for AXI4-Stream VIP providing controlled TREADY
//              backpressure profiles to axis_rd_driver across MM2S verification scenarios:
//              - AXIS_BP_ZERO_DELAY: Wire-speed acceptance (TREADY continuously asserted)
//              - AXIS_BP_MIDWAY_FREEZE: 20-cycle sustained freeze midway (FIFO half-full trigger)
//              - AXIS_BP_FULL_JITTER: Randomized inter-beat jitter [1:3] + final beat TLAST stall

`ifndef AXIS_RD_BACKPRESSURE_SEQ_SV
`define AXIS_RD_BACKPRESSURE_SEQ_SV

typedef enum {
    AXIS_BP_ZERO_DELAY,
    AXIS_BP_MIDWAY_FREEZE,
    AXIS_BP_FULL_JITTER
} axis_bp_mode_e;

class axis_rd_backpressure_seq #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends axis_base_seq #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH);

    typedef axis_seq_item #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(axis_rd_backpressure_seq #(DATA_WIDTH, KEEP_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Operational mode
    axis_bp_mode_e bp_mode = AXIS_BP_FULL_JITTER;

    // Number of beats to accept in this transfer
    int unsigned num_beats     = 16;
    int unsigned freeze_beat   = 7;
    int unsigned freeze_cycles = 20;
    int unsigned min_jitter    = 1;
    int unsigned max_jitter    = 3;
    int unsigned final_stall   = 3;

    function new(string name = "axis_rd_backpressure_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        for (int i = 0; i < num_beats; i++) begin
            `uvm_create(req)
            case (bp_mode)
                AXIS_BP_ZERO_DELAY: begin
                    req.ready_delay = 0;
                end
                AXIS_BP_MIDWAY_FREEZE: begin
                    if (i == freeze_beat) begin
                        req.ready_delay = freeze_cycles;
                    end else begin
                        req.ready_delay = 0;
                    end
                end
                AXIS_BP_FULL_JITTER: begin
                    if (i == num_beats - 1) begin
                        req.ready_delay = final_stall;
                    end else begin
                        req.ready_delay = $urandom_range(min_jitter, max_jitter);
                    end
                end
            endcase
            `uvm_send(req)
        end
    endtask : body

endclass : axis_rd_backpressure_seq

`endif // AXIS_RD_BACKPRESSURE_SEQ_SV

