// File: dma_wr_desc_excess_data_seq.sv
// Description: UVM sequence for S2MM_08 excess stream data ingress.
//              Generates a write descriptor with a smaller buffer capacity (32 bytes)
//              where incoming stream provides excess data (96 bytes) to verify
//              that the DMA write engine cleanly drains excess beats in STATE_DROP_DATA.

`ifndef DMA_WR_DESC_EXCESS_DATA_SEQ_SV
`define DMA_WR_DESC_EXCESS_DATA_SEQ_SV

class dma_wr_desc_excess_data_seq #(
    parameter ADDR_WIDTH = 16,
    parameter LEN_WIDTH  = 20,
    parameter TAG_WIDTH  = 8,
    parameter ID_WIDTH   = 8,
    parameter DEST_WIDTH = 8,
    parameter USER_WIDTH = 1
) extends uvm_sequence #(dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH));

    typedef dma_desc_seq_item #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH) item_type;

    `uvm_object_param_utils(dma_wr_desc_excess_data_seq #(ADDR_WIDTH, LEN_WIDTH, TAG_WIDTH, ID_WIDTH, DEST_WIDTH, USER_WIDTH))

    rand bit [ADDR_WIDTH-1:0] dest_addr;
    rand bit [LEN_WIDTH-1:0]  buffer_len;
    rand bit [TAG_WIDTH-1:0]  xfer_tag;

    // Constraints for excess data write descriptor
    constraint c_excess_data_rules {
        // Hardware Rationale:
        // Destination address is word-aligned.
        // Buffer length is constrained to 32 bytes (8 beats on a 32-bit bus).
        // When the incoming stream supplies more beats than buffer_len, the DMA
        // write engine commits and writes exactly buffer_len bytes to memory,
        // then transitions to STATE_DROP_DATA to drain remaining stream beats
        // with TREADY = 1 until TLAST, preventing pipeline deadlock while
        // protecting memory from buffer overrun corruption.
        dest_addr[1:0] == 2'b00;

        // Ensure positive buffer length
        buffer_len > 0;

        // Memory space bounds check: avoid 16-bit address overflow
        dest_addr + buffer_len <= (1 << ADDR_WIDTH) - 1;

        // Default knobs: 32-byte allocated buffer capacity, Tag 0x0D
        soft dest_addr  == 16'h2000;
        soft buffer_len == 32;
        soft xfer_tag   == 8'h0D;
    }

    function new(string name = "dma_wr_desc_excess_data_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        item_type req;

        req = item_type::type_id::create("wr_excess_data_req");
        start_item(req);

        if (!req.randomize() with {
            trans_type  == DESC_WRITE;
            addr        == local::dest_addr;
            len         == local::buffer_len;
            tag         == local::xfer_tag;
            valid_delay == 0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed for Excess Data Write Descriptor")
        end

        `uvm_info(get_type_name(), $sformatf("Issuing Excess-Data S2MM Write Descriptor (buffer=%0dB, expects 96B ingress stream):\n%s",
                  req.len, req.sprint()), UVM_LOW)

        finish_item(req);

        `uvm_info(get_type_name(), "Excess Data S2MM Write Descriptor accepted by DMA DUT", UVM_LOW)
    endtask : body

endclass : dma_wr_desc_excess_data_seq

`endif // DMA_WR_DESC_EXCESS_DATA_SEQ_SV