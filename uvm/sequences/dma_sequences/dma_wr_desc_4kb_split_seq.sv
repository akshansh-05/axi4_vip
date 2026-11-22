// File: dma_wr_desc_4kb_split_seq.sv
// Description: UVM sequence for S2MM_04 4KB boundary crossing write split.
//              Generates a write descriptor spanning across a 4KB boundary
//              to verify that hardware legally clamps and splits the write burst.

`ifndef DMA_WR_DESC_4KB_SPLIT_SEQ_SV
`define DMA_WR_DESC_4KB_SPLIT_SEQ_SV

class dma_wr_desc_4kb_split_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_wr_desc_4kb_split_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Configurable knobs for 4KB boundary crossing transfers
    rand bit [ADDR_WIDTH-1:0] dest_addr;
    rand bit [LEN_WIDTH-1:0]  buffer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;

    // Constraints guaranteeing 4KB boundary crossing
    constraint c_4kb_split_rules {
        // AXI4 Protocol Rule (ARM IHI 0022E Sec A3.4.1): A burst must never cross a 4KB boundary.
        // Low 12 bits address offset + length must exceed 4096 (0x1000) to force a crossing.
        ((dest_addr & 12'hFFF) + buffer_len) > 13'h1000;

        // Must start prior to the 4KB boundary (offset != 0x000 within 4KB page)
        (dest_addr & 12'hFFF) != 0;

        // Word-aligned destination address (bits [1:0] == 00) for clean aligned memory access
        dest_addr[1:0] == 2'b00;

        // Full 32-bit word multiple length so all 4 byte lanes remain active on every beat
        buffer_len[1:0] == 2'b00;

        // Limit transfer length to fit within 2 AXI bursts (<= 128 bytes) for targeted 2-burst boundary split
        buffer_len inside {[8 : 128]};

        // Prevent memory address wrap-around beyond the 64KB address space (0xFFFF)
        dest_addr + buffer_len <= (1 << ADDR_WIDTH) - 1;

        // Default knobs matching scenario S2MM_04: 32B at 0x2FE0 (offset 0xFE0, 8 beats) + 32B at 0x3000 (offset 0x000, 8 beats)
        soft dest_addr  == 16'h2FE0;
        soft buffer_len == 64;
        soft xfer_tag   == 8'h04;
    }

    function new(string name = "dma_wr_desc_4kb_split_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("wr_4kb_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_WRITE;
            addr        == local::dest_addr;
            len         == local::buffer_len;
            tag         == local::xfer_tag;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for 4KB Boundary Split Write Descriptor")
        end

        `uvm_info(get_type_name(), $sformatf("Sending 4KB Boundary Split S2MM Write Descriptor to DUT:\n%s", req.sprint()), UVM_LOW)

        finish_item(req);

        `uvm_info(get_type_name(), "4KB Boundary Split S2MM Write Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_wr_desc_4kb_split_seq

`endif // DMA_WR_DESC_4KB_SPLIT_SEQ_SV
