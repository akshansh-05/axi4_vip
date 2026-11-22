// File: dma_wr_desc_unaligned_seq.sv
// Description: UVM sequence for S2MM_05 unaligned destination address write transfers.
//              Generates write descriptors with unaligned destination addresses (+1, +2, +3 bytes)
//              and constant word-multiple lengths (16 bytes) to verify address offset decoding,
//              stream byte shifting into target AXI lanes, and initial WSTRB masking.

`ifndef DMA_WR_DESC_UNALIGNED_SEQ_SV
`define DMA_WR_DESC_UNALIGNED_SEQ_SV

class dma_wr_desc_unaligned_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_wr_desc_unaligned_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable knobs for unaligned write transfers
    rand bit [ADDR_WIDTH-1:0] dest_addr;
    rand bit [LEN_WIDTH-1:0]  buffer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;

    // Constraints for unaligned write operation
    constraint c_unaligned_rules {
        // Hardware Rationale:
        // AXI4 allows unaligned transfer start addresses. On a 32-bit (4-byte) data bus,
        // dest_addr[1:0] determines the starting byte offset:
        //   - 2'b01 (+1 byte): Destination starts at byte lane 1 of word.
        //   - 2'b10 (+2 byte): Destination starts at byte lane 2 of word.
        //   - 2'b11 (+3 byte): Destination starts at byte lane 3 of word.
        // The DMA RTL barrel shifter shifts stream byte 0 into byte lane dest_addr[1:0],
        // while preceding lanes in Beat 0 are deasserted via initial WSTRB masking:
        //   strb_offset_mask = {4{1'b1}} << dest_addr[1:0].
        dest_addr[1:0] != 2'b00;

        // Ensure non-zero transfer length
        buffer_len > 0;

        // Memory space bounds check: avoid 16-bit address overflow
        dest_addr + buffer_len <= (1 << ADDR_WIDTH) - 1;

        // Default knobs: pure 16-byte transfer (word multiple) with +1B offset
        soft dest_addr  == 16'h2001; // +1 byte offset (Byte lane 1)
        soft buffer_len == 16;       // 16 bytes total (4 full stream beats)
        soft xfer_tag   == 8'h05;    // Unique transfer tracking tag
    }

    function new(string name = "dma_wr_desc_unaligned_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("wr_unaligned_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_WRITE;
            addr        == local::dest_addr;
            len         == local::buffer_len;
            tag         == local::xfer_tag;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Unaligned Write Descriptor")
        end

        `uvm_info(get_type_name(), $sformatf("Issuing Unaligned S2MM Write Descriptor (offset +%0d bytes):\n%s",
                  req.addr[1:0], req.sprint()), UVM_LOW)

        finish_item(req);

        `uvm_info(get_type_name(), "Unaligned S2MM Write Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_wr_desc_unaligned_seq

`endif // DMA_WR_DESC_UNALIGNED_SEQ_SV