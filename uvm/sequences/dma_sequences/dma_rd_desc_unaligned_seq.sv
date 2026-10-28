// File: dma_rd_desc_unaligned_seq.sv
// Description: UVM sequence for MM2S_04 unaligned start address read transfers.
//              Generates a read descriptor with an unaligned start address
//              (offsets +1, +2, or +3 bytes) to verify barrel-shifter alignment.

`ifndef DMA_RD_DESC_UNALIGNED_SEQ_SV
`define DMA_RD_DESC_UNALIGNED_SEQ_SV

class dma_rd_desc_unaligned_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_rd_desc_unaligned_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable knobs for unaligned read transfers
    rand bit [ADDR_WIDTH-1:0] start_addr;
    rand bit [LEN_WIDTH-1:0]  xfer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;
    rand bit [ID_WIDTH-1:0]   stream_id;
    rand bit [DEST_WIDTH-1:0] stream_dest;
    rand bit [USER_WIDTH-1:0] stream_user;

    // Constraints for unaligned read operation
    constraint c_unaligned_rules {
        // Start address must be unaligned (not a 4-byte word boundary)
        start_addr[1:0] != 2'b00;

        // Non-zero transfer length
        xfer_len > 0;

        // Prevent address wrap beyond 64KB memory space
        start_addr + xfer_len <= (1 << ADDR_WIDTH) - 1;

        // Default knobs matching scenario MM2S_04 sub-iteration 1 (+1B offset)
        soft start_addr  == 16'h1001; // +1 byte offset
        soft xfer_len    == 15;       // 15 bytes total
        soft xfer_tag    == 8'h04;    // Tag 0x04
        soft stream_id   == '0;
        soft stream_dest == '0;
        soft stream_user == '0;
    }

    function new(string name = "dma_rd_desc_unaligned_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("rd_unaligned_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_READ;
            addr        == local::start_addr;
            len         == local::xfer_len;
            tag         == local::xfer_tag;
            id          == local::stream_id;
            dest        == local::stream_dest;
            user        == local::stream_user;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Unaligned Read Descriptor")
        end

        `uvm_info(get_type_name(), $sformatf("Issuing Unaligned MM2S Read Descriptor: addr=0x%04h (offset +%0d), len=%0d bytes, tag=0x%02h",
                  req.addr, req.addr[1:0], req.len, req.tag), UVM_LOW)

        finish_item(req);

        `uvm_info(get_type_name(), "Unaligned MM2S Read Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_rd_desc_unaligned_seq

`endif // DMA_RD_DESC_UNALIGNED_SEQ_SV
