// File: dma_wr_desc_b2b_seq.sv
// Description: UVM sequence for S2MM_02: Back-to-Back (B2B) Pipelined Descriptor Writes.
//              Generates two consecutive write descriptors without inter-descriptor delays
//              to verify DMA write descriptor pipelining and status tracking credit management.

`ifndef DMA_WR_DESC_B2B_SEQ_SV
`define DMA_WR_DESC_B2B_SEQ_SV

class dma_wr_desc_b2b_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_wr_desc_b2b_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    // Knobs for Descriptor 1
    rand bit [ADDR_WIDTH-1:0] dest_addr1;
    rand bit [LEN_WIDTH-1:0]  buffer_len1;
    rand bit [TAG_WIDTH-1:0]  xfer_tag1;

    // Knobs for Descriptor 2
    rand bit [ADDR_WIDTH-1:0] dest_addr2;
    rand bit [LEN_WIDTH-1:0]  buffer_len2;
    rand bit [TAG_WIDTH-1:0]  xfer_tag2;

    // Timing Knob: Inter-descriptor delay cycles between Descriptor 1 and Descriptor 2 (default: 0 for seamless pipelined issuance)
    rand int unsigned         inter_desc_delay;

    constraint c_b2b_rules {
        // Transfer lengths must fit within a single AXI burst (1 to 16 beats = 4 to 64 bytes)
        buffer_len1 inside {[4 : 64]};
        buffer_len2 inside {[4 : 64]};

        // Word-aligned destination addresses (bits [1:0] == 00) for baseline single burst
        dest_addr1[1:0]  == 2'b00;
        dest_addr2[1:0]  == 2'b00;

        // Full 32-bit word multiple lengths (all 4 byte lanes active per beat)
        buffer_len1[1:0] == 2'b00;
        buffer_len2[1:0] == 2'b00;

        // Prevent address wrap-around beyond top of 64KB address space (0xFFFF)
        dest_addr1 + buffer_len1 <= (1 << ADDR_WIDTH) - 1;
        dest_addr2 + buffer_len2 <= (1 << ADDR_WIDTH) - 1;

        // Distinct non-overlapping buffers: Buffer 1 ends before Buffer 2 starts, or vice versa.
        // Prevents write-after-write (WAW) memory corruption between back-to-back packets.
        (dest_addr1 + buffer_len1 <= dest_addr2) || (dest_addr2 + buffer_len2 <= dest_addr1);

        // Inter-descriptor delay defaults to 0 for seamless wire-speed back-to-back issuance
        soft inter_desc_delay == 0;

        // Default knobs matching scenario S2MM_02
        soft dest_addr1  == 16'h2000;
        soft buffer_len1 == 64;
        soft xfer_tag1   == 8'h01;

        soft dest_addr2  == 16'h3000;
        soft buffer_len2 == 64;
        soft xfer_tag2   == 8'h02;
    }

    function new(string name = "dma_wr_desc_b2b_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req1;
        item_type req2;

        `uvm_info(get_type_name(), "Executing S2MM_02 B2B Pipelined Write Descriptors", UVM_LOW)

        // Descriptor 1: Issue immediately with zero delay
        req1 = item_type::type_id::create("wr_b2b_req1");
        start_item(req1);
        if (!req1.randomize() with {
            trans_type  == DESC_WRITE;
            addr        == local::dest_addr1;
            len         == local::buffer_len1;
            tag         == local::xfer_tag1;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for B2B Write Descriptor 1")
        end
        `uvm_info(get_type_name(), $sformatf("Sending S2MM Write Descriptor 1 to DUT:\n%s", req1.sprint()), UVM_LOW)
        finish_item(req1);
        `uvm_info(get_type_name(), "S2MM Descriptor 1 accepted by DMA DUT", UVM_LOW)

        // Descriptor 2: Issue immediately after Descriptor 1 without bubbles (or with user-configured inter_desc_delay)
        req2 = item_type::type_id::create("wr_b2b_req2");
        start_item(req2);
        if (!req2.randomize() with {
            trans_type  == DESC_WRITE;
            addr        == local::dest_addr2;
            len         == local::buffer_len2;
            tag         == local::xfer_tag2;
            valid_delay == local::inter_desc_delay;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for B2B Write Descriptor 2")
        end
        `uvm_info(get_type_name(), $sformatf("Sending S2MM Write Descriptor 2 to DUT:\n%s", req2.sprint()), UVM_LOW)
        finish_item(req2);
        `uvm_info(get_type_name(), "S2MM Descriptor 2 accepted by DMA DUT (pipelining confirmed)", UVM_LOW)
    endtask : body

endclass : dma_wr_desc_b2b_seq

`endif // DMA_WR_DESC_B2B_SEQ_SV
