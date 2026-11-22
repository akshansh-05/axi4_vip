// File: dma_wr_desc_nominal_seq.sv
// Description: UVM sequence for S2MM_01 nominal single-burst write transfers.
//              Generates a baseline single-burst write descriptor (4 to 64 bytes)
//              with word-aligned destination address and full byte capacity.

`ifndef DMA_WR_DESC_NOMINAL_SEQ_SV
`define DMA_WR_DESC_NOMINAL_SEQ_SV

class dma_wr_desc_nominal_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_wr_desc_nominal_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    rand bit [ADDR_WIDTH-1:0] dest_addr;
    rand bit [LEN_WIDTH-1:0]  buffer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;

    constraint c_nominal_rules {
        buffer_len inside {[4 : 64]};
        dest_addr[1:0] == 2'b00;
        buffer_len[1:0] == 2'b00;
        dest_addr + buffer_len <= (1 << ADDR_WIDTH) - 1;

        soft dest_addr  == 16'h2000;
        soft buffer_len == 64;
        soft xfer_tag   == 8'h01;
    }

    function new(string name = "dma_wr_desc_nominal_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("wr_nominal_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_WRITE;
            addr        == local::dest_addr;
            len         == local::buffer_len;
            tag         == local::xfer_tag;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Write Descriptor Nominal Item")
        end

        `uvm_info(get_type_name(), $sformatf("Sending S2MM Write Descriptor to DUT:\n%s", req.sprint()), UVM_LOW)
        finish_item(req);
        `uvm_info(get_type_name(), "S2MM Write Descriptor command accepted by DMA DUT!", UVM_LOW)
    endtask : body

endclass : dma_wr_desc_nominal_seq

`endif // DMA_WR_DESC_NOMINAL_SEQ_SV

