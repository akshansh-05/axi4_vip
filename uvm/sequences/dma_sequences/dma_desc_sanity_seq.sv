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

    function new(string name = "dma_rd_desc_sanity_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_READ;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Read Descriptor")
        end

        `uvm_info(get_type_name(), $sformatf("Sending Read Descriptor to driver:\n%s", req.sprint()), UVM_LOW)
        finish_item(req);
        `uvm_info(get_type_name(), "Read Descriptor sanity item handshake completed!", UVM_LOW)
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

    function new(string name = "dma_wr_desc_sanity_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_WRITE;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Write Descriptor")
        end

        `uvm_info(get_type_name(), $sformatf("Sending Write Descriptor to driver:\n%s", req.sprint()), UVM_LOW)
        finish_item(req);
        `uvm_info(get_type_name(), "Write Descriptor sanity item handshake completed!", UVM_LOW)
    endtask : body

endclass : dma_wr_desc_sanity_seq

`endif // DMA_DESC_SANITY_SEQ_SV
