// File: dma_rd_desc_multiburst_seq.sv
// Description: UVM sequence for MM2S_02 multi-burst read transfers.
//              Generates a descriptor transfer length exceeding single-burst capacity
//              (> 64 bytes) with word-aligned addresses and full byte enables.

`ifndef DMA_RD_DESC_MULTIBURST_SEQ_SV
`define DMA_RD_DESC_MULTIBURST_SEQ_SV

class dma_rd_desc_multiburst_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_rd_desc_multiburst_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable knobs for multi-burst transfers
    rand bit [ADDR_WIDTH-1:0] start_addr;
    rand bit [LEN_WIDTH-1:0]  xfer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;
    rand bit [ID_WIDTH-1:0]   stream_id;
    rand bit [DEST_WIDTH-1:0] stream_dest;
    rand bit [USER_WIDTH-1:0] stream_user;

    // Constraints targeting clean multi-burst operation
    constraint c_multiburst_rules {
        // Must be strictly greater than 64 bytes (1 AXI burst) to exercise burst slicing
        xfer_len > 64;

        // Word aligned starting address
        start_addr[1:0] == 2'b00;

        // Full word multiple so all byte lanes are active on every beat
        xfer_len[1:0] == 2'b00;

        // Prevent address wrap beyond 64KB memory space
        start_addr + xfer_len <= (1 << ADDR_WIDTH) - 1;

        // Default knobs matching scenario MM2S_02
        soft start_addr  == 16'h1000;
        soft xfer_len    == 256;      // 256 bytes = 64 beats = 4 full bursts of 16 beats
        soft xfer_tag    == 8'h02;    // Tag 0x02 for MM2S_02
        soft stream_id   == '0;
        soft stream_dest == '0;
        soft stream_user == '0;
    }

    function new(string name = "dma_rd_desc_multiburst_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("rd_multiburst_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_READ;
            addr        == local::start_addr;
            len         == local::xfer_len;
            tag         == local::xfer_tag;
        // ID Fields are set to zero as per scenario MM2S_02
            id          == local::stream_id;
            dest        == local::stream_dest;
            user        == local::stream_user;
        // Valid delay is set to zero as per scenario MM2S_02
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Read Descriptor Multi-Burst Item")
        end

        `uvm_info(get_type_name(), $sformatf("Issuing Multi-Burst MM2S Read Descriptor: addr=0x%04h, len=%0d bytes (%0d bursts), tag=0x%02h",
                  req.addr, req.len, (req.len + 63) / 64, req.tag), UVM_LOW)

        finish_item(req);

        `uvm_info(get_type_name(), "Multi-Burst MM2S Read Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_rd_desc_multiburst_seq

`endif // DMA_RD_DESC_MULTIBURST_SEQ_SV
