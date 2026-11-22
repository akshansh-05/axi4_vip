// File: dma_wr_desc_multiburst_seq.sv
// Description: UVM sequence for S2MM_03 multi-burst write transfers (>16 Beats).
//              Generates a write descriptor transfer length exceeding single-burst capacity
//              (> 64 bytes) with word-aligned addresses and full byte enables.

`ifndef DMA_WR_DESC_MULTIBURST_SEQ_SV
`define DMA_WR_DESC_MULTIBURST_SEQ_SV

class dma_wr_desc_multiburst_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_wr_desc_multiburst_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable knobs for multi-burst write transfers
    rand bit [ADDR_WIDTH-1:0] dest_addr;
    rand bit [LEN_WIDTH-1:0]  buffer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;

    // Constraints targeting clean multi-burst operation
    constraint c_multiburst_rules {
        // Must be strictly greater than 64 bytes (16 beats) to exercise hardware burst slicing
        buffer_len > 64;

        // Word-aligned destination address (bits [1:0] == 00) for clean aligned write bursts
        dest_addr[1:0] == 2'b00;

        // Full 32-bit word multiple length so all 4 byte lanes remain active on every beat
        buffer_len[1:0] == 2'b00;

        // Prevent memory address wrap-around beyond the 64KB address space (0xFFFF)
        dest_addr + buffer_len <= (1 << ADDR_WIDTH) - 1;

        // Default knobs matching scenario S2MM_03: 256 bytes = 64 beats = 4 full bursts of 16 beats
        soft dest_addr  == 16'h2000;
        soft buffer_len == 256;
        soft xfer_tag   == 8'h03;
    }

    function new(string name = "dma_wr_desc_multiburst_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("wr_multiburst_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_WRITE;
            addr        == local::dest_addr;
            len         == local::buffer_len;
            tag         == local::xfer_tag;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Write Descriptor Multi-Burst Item")
        end

        `uvm_info(get_type_name(), $sformatf("Sending Multi-Burst S2MM Write Descriptor to DUT:\n%s", req.sprint()), UVM_LOW)

        finish_item(req);

        `uvm_info(get_type_name(), "Multi-Burst S2MM Write Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_wr_desc_multiburst_seq

`endif // DMA_WR_DESC_MULTIBURST_SEQ_SV
