// File: dma_rd_desc_backpressure_seq.sv
// Description: UVM sequence for MM2S_06 pipeline backpressure and flow control testing.
//              Generates read descriptors targeted for backpressure verification across
//              ARREADY stalls, Skid FIFO watermarks, and stream receiver freezes.

`ifndef DMA_RD_DESC_BACKPRESSURE_SEQ_SV
`define DMA_RD_DESC_BACKPRESSURE_SEQ_SV

class dma_rd_desc_backpressure_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_rd_desc_backpressure_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable knobs for backpressure verification
    rand bit [ADDR_WIDTH-1:0] start_addr;
    rand bit [LEN_WIDTH-1:0]  xfer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;
    rand bit [ID_WIDTH-1:0]   stream_id;
    rand bit [DEST_WIDTH-1:0] stream_dest;
    rand bit [USER_WIDTH-1:0] stream_user;
    rand int unsigned         valid_delay;

    // Constraints for backpressure test descriptors
    constraint c_bp_rules {
        xfer_len inside {[4 : 64]};
        start_addr[1:0] == 2'b00;
        xfer_len[1:0]   == 2'b00;
        start_addr + xfer_len <= (1 << ADDR_WIDTH) - 1;

        soft start_addr   == 16'h1000;
        soft xfer_len     == 64;
        soft xfer_tag     == 8'h0A;
        soft stream_id    == '0;
        soft stream_dest  == '0;
        soft stream_user  == '0;
        soft valid_delay  == 0;
    }

    function new(string name = "dma_rd_desc_backpressure_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("rd_bp_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_READ;
            addr        == local::start_addr;
            len         == local::xfer_len;
            tag         == local::xfer_tag;
            id          == local::stream_id;
            dest        == local::stream_dest;
            user        == local::stream_user;
            valid_delay == local::valid_delay;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Read Descriptor Backpressure Item")
        end

        `uvm_info(get_type_name(), $sformatf("Issuing Backpressure MM2S Read Descriptor: addr=0x%04h, len=%0d bytes, tag=0x%02h",
                  req.addr, req.len, req.tag), UVM_LOW)

        finish_item(req);

        `uvm_info(get_type_name(), "Backpressure MM2S Read Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_rd_desc_backpressure_seq

`endif // DMA_RD_DESC_BACKPRESSURE_SEQ_SV

