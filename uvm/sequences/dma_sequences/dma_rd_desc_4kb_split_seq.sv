// File: dma_rd_desc_4kb_split_seq.sv
// Description: UVM sequence for MM2S_03 4KB boundary crossing read split.
//              Generates a read descriptor spanning across a 4KB boundary
//              to verify that hardware legally clamps and splits the transfer.

`ifndef DMA_RD_DESC_4KB_SPLIT_SEQ_SV
`define DMA_RD_DESC_4KB_SPLIT_SEQ_SV

class dma_rd_desc_4kb_split_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_rd_desc_4kb_split_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable knobs for 4KB boundary crossing transfers
    rand bit [ADDR_WIDTH-1:0] start_addr;
    rand bit [LEN_WIDTH-1:0]  xfer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;
    rand bit [ID_WIDTH-1:0]   stream_id;
    rand bit [DEST_WIDTH-1:0] stream_dest;
    rand bit [USER_WIDTH-1:0] stream_user;

    // Constraints guaranteeing 4KB boundary crossing
    constraint c_4kb_split_rules {
        // Must cross a 4KB boundary (low 12 bits offset + length > 4096)
        ((start_addr & 12'hFFF) + xfer_len) > 13'h1000;

        // Must start prior to the 4KB boundary
        (start_addr & 12'hFFF) != 0;

        // Word aligned start address
        start_addr[1:0] == 2'b00;

        // Full word multiple length
        xfer_len[1:0] == 2'b00;

        // Limit transfer length to fit within 2 AXI bursts (<= 128 bytes)
        xfer_len inside {[8 : 128]};

        // Prevent address wrap beyond 64KB memory space
        start_addr + xfer_len <= (1 << ADDR_WIDTH) - 1;

        // Default knobs matching scenario MM2S_03
        soft start_addr  == 16'h0FE0; // 32 bytes away from 4KB boundary at 0x1000
        soft xfer_len    == 64;       // 64 bytes total (32B in burst 1, 32B in burst 2)
        soft xfer_tag    == 8'h03;    // Tag 0x03 for MM2S_03
        soft stream_id   == '0;
        soft stream_dest == '0;
        soft stream_user == '0;
    }

    function new(string name = "dma_rd_desc_4kb_split_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("rd_4kb_req");
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
            `uvm_fatal(get_type_name(), "Randomization failed for 4KB Boundary Split Read Descriptor")
        end

        `uvm_info(get_type_name(), $sformatf("Issuing 4KB Split Read Descriptor: addr=0x%04h, len=%0d bytes, tag=0x%02h",
                  req.addr, req.len, req.tag), UVM_LOW)

        finish_item(req);

        `uvm_info(get_type_name(), "4KB Split Read Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_rd_desc_4kb_split_seq

`endif // DMA_RD_DESC_4KB_SPLIT_SEQ_SV
