// File: dma_wr_desc_early_term_seq.sv
// Description: UVM sequence for S2MM_07 early stream termination.
//              Generates a write descriptor requesting a larger buffer length
//              where the incoming stream terminates early via TLAST before the
//              descriptor length is fulfilled.

`ifndef DMA_WR_DESC_EARLY_TERM_SEQ_SV
`define DMA_WR_DESC_EARLY_TERM_SEQ_SV

class dma_wr_desc_early_term_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_wr_desc_early_term_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    rand bit [ADDR_WIDTH-1:0] dest_addr;
    rand bit [LEN_WIDTH-1:0]  buffer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;

    // Constraints for early-termination descriptors
    constraint c_early_term_rules {
        // Hardware Rationale:
        // Destination address is word-aligned.
        // The descriptor promises a buffer capacity (e.g., 64B or 128B), prompting
        // the DMA engine to commit an AXI write burst with AWLEN = 15 (16 beats).
        // When the incoming stream asserts TLAST early (e.g., at beat 7 or 11),
        // the DMA FSM cannot abort the active AXI burst without hanging the slave.
        // Instead, the DMA transitions to STATE_FINISH_BURST and zero-pads the
        // remaining beats of the in-flight burst with WSTRB = 4'b0000 and WDATA = 0,
        // safely completing the AXI burst and cancelling any subsequent bursts.
        dest_addr[1:0] == 2'b00;

        // Ensure positive buffer length
        buffer_len > 0;

        // Memory space bounds check: avoid 16-bit address overflow
        dest_addr + buffer_len <= (1 << ADDR_WIDTH) - 1;

        // Default knobs: 64-byte promised buffer length, Tag 0x0B
        soft dest_addr  == 16'h2000;
        soft buffer_len == 64;
        soft xfer_tag   == 8'h0B;
    }

    function new(string name = "dma_wr_desc_early_term_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("wr_early_term_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_WRITE;
            addr        == local::dest_addr;
            len         == local::buffer_len;
            tag         == local::xfer_tag;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Early Termination Write Descriptor")
        end

        `uvm_info(get_type_name(), $sformatf("Issuing Early-Termination S2MM Write Descriptor (promised %0dB, expects early stream TLAST):\n%s",
                  req.len, req.sprint()), UVM_LOW)

        finish_item(req);

        `uvm_info(get_type_name(), "Early Termination S2MM Write Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_wr_desc_early_term_seq

`endif // DMA_WR_DESC_EARLY_TERM_SEQ_SV