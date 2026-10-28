// File: dma_rd_desc_nominal_seq.sv
// Description: UVM sequence for MM2S_01 nominal single-burst read transfers.
//              Generates a baseline single-burst read descriptor (1 to 64 bytes)
//              with word-aligned start address and full byte enables.

`ifndef DMA_RD_DESC_NOMINAL_SEQ_SV
`define DMA_RD_DESC_NOMINAL_SEQ_SV

class dma_rd_desc_nominal_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_rd_desc_nominal_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable knobs for nominal single-burst transfers
    rand bit [ADDR_WIDTH-1:0] start_addr;
    rand bit [LEN_WIDTH-1:0]  xfer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;
    rand bit [ID_WIDTH-1:0]   stream_id;
    rand bit [DEST_WIDTH-1:0] stream_dest;
    rand bit [USER_WIDTH-1:0] stream_user;

    // Constraints for nominal single-burst operation
    constraint c_nominal_rules {
        // Fits within a single AXI burst (1 to 16 beats = 4 to 64 bytes)
        xfer_len inside {[4 : 64]};

        // Word aligned starting address
        start_addr[1:0] == 2'b00;

        // Full word multiple so all byte lanes are active
        xfer_len[1:0] == 2'b00;

        // Prevent address wrap beyond 64KB memory space
        start_addr + xfer_len <= (1 << ADDR_WIDTH) - 1;

        // Default knobs matching scenario MM2S_01
        soft start_addr  == 16'h1000;
        soft xfer_len    == 64;       // 64 bytes = 16 beats of 4 bytes
        soft xfer_tag    == 8'h01;    // Tag 0x01 for MM2S_01
        soft stream_id   == '0;
        soft stream_dest == '0;
        soft stream_user == '0;
    }

    function new(string name = "dma_rd_desc_nominal_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("rd_nominal_req");
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
            `uvm_fatal(get_type_name(), "Randomization failed for Read Descriptor Nominal Item")
        end

        `uvm_info(get_type_name(), $sformatf("Issuing Nominal Single-Burst MM2S Read Descriptor: addr=0x%04h, len=%0d bytes, tag=0x%02h",
                  req.addr, req.len, req.tag), UVM_LOW)

        finish_item(req);

        `uvm_info(get_type_name(), "Nominal MM2S Read Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_rd_desc_nominal_seq

`endif // DMA_RD_DESC_NOMINAL_SEQ_SV
