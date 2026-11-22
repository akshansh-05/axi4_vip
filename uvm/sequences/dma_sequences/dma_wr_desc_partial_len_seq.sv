// File: dma_wr_desc_partial_len_seq.sv
// Description: UVM sequence for S2MM_06 non-word-multiple transfer lengths.
//              Generates write descriptors with non-word-multiple byte lengths (13B, 14B, 15B)
//              at aligned addresses (0x2000) to isolate and verify trailing byte lane deassertion
//              (WSTRB) on the final AXI write beat.

`ifndef DMA_WR_DESC_PARTIAL_LEN_SEQ_SV
`define DMA_WR_DESC_PARTIAL_LEN_SEQ_SV

class dma_wr_desc_partial_len_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_wr_desc_partial_len_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable knobs for partial-length write transfers
    rand bit [ADDR_WIDTH-1:0] dest_addr;
    rand bit [LEN_WIDTH-1:0]  buffer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;

    // Constraints for non-word-multiple operation
    constraint c_partial_len_rules {
        // Hardware Rationale:
        // Destination address is word-aligned (dest_addr[1:0] == 2'b00) so that Beat 0
        // has all byte lanes enabled (WSTRB = 4'b1111).
        // Transfer length buffer_len[1:0] != 2'b00 forces a non-word-multiple length.
        // On the final beat of the AXI write burst, the DMA engine deasserts trailing WSTRB bits:
        //   - buffer_len % 4 == 1: 1 active byte in lane 0 -> WSTRB = 4'b0001
        //   - buffer_len % 4 == 2: 2 active bytes in lanes [1:0] -> WSTRB = 4'b0011
        //   - buffer_len % 4 == 3: 3 active bytes in lanes [2:0] -> WSTRB = 4'b0111
        dest_addr[1:0] == 2'b00;

        // Length must NOT be a multiple of 4 bytes
        buffer_len[1:0] != 2'b00;

        // Transfer length within single burst capacity
        buffer_len inside {[4 : 63]};

        // Memory space bounds check: avoid 16-bit address overflow
        dest_addr + buffer_len <= (1 << ADDR_WIDTH) - 1;

        // Default knobs matching scenario S2MM_06 sub-iteration 1 (13B -> rem 1B)
        soft dest_addr  == 16'h2000;
        soft buffer_len == 13;       // 13 bytes: rem = 1B -> expected final WSTRB = 4'b0001
        soft xfer_tag   == 8'h08;    // Tag 0x08
    }

    function new(string name = "dma_wr_desc_partial_len_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("wr_partial_len_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_WRITE;
            addr        == local::dest_addr;
            len         == local::buffer_len;
            tag         == local::xfer_tag;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Partial-Length Write Descriptor")
        end

        `uvm_info(get_type_name(), $sformatf("Issuing Partial-Length S2MM Write Descriptor (rem=%0dB):\n%s",
                  req.len[1:0], req.sprint()), UVM_LOW)

        finish_item(req);

        `uvm_info(get_type_name(), "Partial-Length S2MM Write Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_wr_desc_partial_len_seq

`endif // DMA_WR_DESC_PARTIAL_LEN_SEQ_SV