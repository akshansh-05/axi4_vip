// File: dma_wr_desc_skew_seq.sv
// Description: UVM sequence for S2MM_10 asynchronous control-data timing skew.
//              Supports controllable start delay (valid_delay) to model both
//              Data-First (descriptor delayed) and Desc-First timing scenarios.

`ifndef DMA_WR_DESC_SKEW_SEQ_SV
`define DMA_WR_DESC_SKEW_SEQ_SV

class dma_wr_desc_skew_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_wr_desc_skew_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    rand bit [ADDR_WIDTH-1:0] dest_addr;
    rand bit [LEN_WIDTH-1:0]  buffer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;
    rand int unsigned         issue_delay; // Clock cycle delay before issuing descriptor

    // Hardware Rationale:
    // Word-aligned destination address to isolate timing skew behavior from alignment shifting.
    // Buffer length is constrained to positive length within 16-bit address space.
    // issue_delay controls descriptor issue latency (in clock cycles) to test asynchronous
    // skew relative to stream ingress.
    constraint c_skew_rules {
        dest_addr[1:0] == 2'b00;
        buffer_len > 0;
        dest_addr + buffer_len <= (1 << ADDR_WIDTH) - 1;

        soft dest_addr   == 16'h2000;
        soft buffer_len  == 64;
        soft xfer_tag    == 8'h0E;
        soft issue_delay == 0;
    }

    function new(string name = "dma_wr_desc_skew_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("wr_skew_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_WRITE;
            addr        == local::dest_addr;
            len         == local::buffer_len;
            tag         == local::xfer_tag;
            valid_delay == local::issue_delay;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Skew Write Descriptor")
        end

        `uvm_info(get_type_name(), $sformatf("Issuing Skew S2MM Write Descriptor (valid_delay=%0d cycles):\n%s",
                  req.valid_delay, req.sprint()), UVM_LOW)

        finish_item(req);

        `uvm_info(get_type_name(), "Skew S2MM Write Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_wr_desc_skew_seq

`endif // DMA_WR_DESC_SKEW_SEQ_SV
