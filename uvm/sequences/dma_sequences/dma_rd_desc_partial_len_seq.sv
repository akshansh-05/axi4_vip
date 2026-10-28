// File: dma_rd_desc_partial_len_seq.sv
// Description: UVM sequence for MM2S_05 non-word-multiple transfer lengths.
//              Generates a read descriptor with a non-word-multiple byte length
//              to verify trailing byte lane deassertion (TKEEP) on the final beat.

`ifndef DMA_RD_DESC_PARTIAL_LEN_SEQ_SV
`define DMA_RD_DESC_PARTIAL_LEN_SEQ_SV

class dma_rd_desc_partial_len_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_rd_desc_partial_len_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable knobs for partial-length read transfers
    rand bit [ADDR_WIDTH-1:0] start_addr;
    rand bit [LEN_WIDTH-1:0]  xfer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;
    rand bit [ID_WIDTH-1:0]   stream_id;
    rand bit [DEST_WIDTH-1:0] stream_dest;
    rand bit [USER_WIDTH-1:0] stream_user;

    // Constraints for non-word-multiple operation
    constraint c_partial_len_rules {
        // Start address must be word-aligned to isolate trailing TKEEP masking
        start_addr[1:0] == 2'b00;

        // Length must NOT be a multiple of 4 bytes (forces partial final beat)
        xfer_len[1:0] != 2'b00;

        // Transfer length non-zero and within single burst capacity
        xfer_len inside {[1 : 63]};

        // Prevent address wrap beyond 64KB memory space
        start_addr + xfer_len <= (1 << ADDR_WIDTH) - 1;

        // Default knobs matching scenario MM2S_05 sub-iteration 1 (13B -> rem 1B)
        soft start_addr  == 16'h1000;
        soft xfer_len    == 13;       // 13 bytes: rem = 1B -> expected TKEEP = 4'b0001
        soft xfer_tag    == 8'h07;    // Tag 0x07
        soft stream_id   == '0;
        soft stream_dest == '0;
        soft stream_user == '0;
    }

    function new(string name = "dma_rd_desc_partial_len_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("rd_partial_len_req");
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
            `uvm_fatal(get_type_name(), "Randomization failed for Partial-Length Read Descriptor")
        end

        finish_item(req);

        `uvm_info(get_type_name(), "Partial-Length MM2S Read Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_rd_desc_partial_len_seq

`endif // DMA_RD_DESC_PARTIAL_LEN_SEQ_SV
