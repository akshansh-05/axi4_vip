// File: dma_desc_sanity_seq.sv
// Description: Smoke sequences to drive Read and Write descriptors into the DMA DUT.
//              Used to verify that the UVM drivers successfully drive interface signals
//              and complete Valid/Ready handshakes.

`ifndef DMA_DESC_SANITY_SEQ_SV
`define DMA_DESC_SANITY_SEQ_SV

// 1. Read Descriptor Sanity Sequence (MM2S)
class dma_rd_desc_sanity_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_rd_desc_sanity_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable knobs with clean sanity defaults
    rand bit [ADDR_WIDTH-1:0] start_addr;
    rand bit [LEN_WIDTH-1:0]  xfer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;

    constraint c_rd_sanity_defaults {
        soft start_addr == 16'h1000; // Word-aligned base address
        soft xfer_len   == 64;       // 64 bytes = 16 beats of 4 bytes
        soft xfer_tag   == 8'h01;    // Tag #1
    }

    function new(string name = "dma_rd_desc_sanity_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("rd_desc_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_READ;
            addr        == local::start_addr;
            len         == local::xfer_len;
            tag         == local::xfer_tag;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Read Descriptor Sanity Item")
        end

        `uvm_info(get_type_name(), $sformatf("Sending MM2S Read Descriptor to DUT:\n%s", req.sprint()), UVM_LOW)
        finish_item(req);
        `uvm_info(get_type_name(), "MM2S Read Descriptor command accepted by DMA DUT!", UVM_LOW)
    endtask : body

endclass : dma_rd_desc_sanity_seq

// 2. Write Descriptor Sanity Sequence (S2MM)

class dma_wr_desc_sanity_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_wr_desc_sanity_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable knobs with clean sanity defaults
    rand bit [ADDR_WIDTH-1:0] dest_addr;
    rand bit [LEN_WIDTH-1:0]  buffer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;

    constraint c_wr_sanity_defaults {
        soft dest_addr  == 16'h2000; // Destination memory address
        soft buffer_len == 64;       // 64 bytes buffer capacity
        soft xfer_tag   == 8'h02;    // Tag #2
    }

    function new(string name = "dma_wr_desc_sanity_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("wr_desc_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_WRITE;
            addr        == local::dest_addr;
            len         == local::buffer_len;
            tag         == local::xfer_tag;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Write Descriptor Sanity Item")
        end

        `uvm_info(get_type_name(), $sformatf("Sending S2MM Write Descriptor to DUT:\n%s", req.sprint()), UVM_LOW)
        finish_item(req);
        `uvm_info(get_type_name(), "S2MM Write Descriptor command accepted by DMA DUT!", UVM_LOW)
    endtask : body

endclass : dma_wr_desc_sanity_seq

`endif // DMA_DESC_SANITY_SEQ_SV
