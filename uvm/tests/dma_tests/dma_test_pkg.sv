// File: dma_test_pkg.sv
// Description: Package bundling all UVM test classes for DMA Standalone and Subsystem verification.

`ifndef DMA_TEST_PKG_SV
`define DMA_TEST_PKG_SV

package dma_test_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import tb_params_pkg::*;
    import axi_mm_pkg::*;
    import dma_desc_pkg::*;
    import axis_pkg::*;
    import dma_subsystem_env_pkg::*;
    import dma_seq_pkg::*;

    `include "dma_base_test.sv"
    `include "dma_sanity_test.sv"
    `include "dma_rd_nominal_test.sv"
    `include "dma_rd_multiburst_test.sv"
    `include "dma_rd_4kb_split_test.sv"
    `include "dma_rd_unaligned_test.sv"
    `include "dma_rd_partial_len_test.sv"
    `include "dma_rd_backpressure_test.sv"
    `include "dma_wr_nominal_test.sv"
    `include "dma_wr_b2b_test.sv"
    `include "dma_wr_multiburst_test.sv"
    `include "dma_wr_4kb_split_test.sv"
    `include "dma_wr_unaligned_test.sv"
    `include "dma_wr_partial_len_test.sv"
    `include "dma_wr_early_term_test.sv"
    `include "dma_wr_excess_data_test.sv"
    `include "dma_wr_skew_test.sv"
    `include "dma_wr_stream_bubble_test.sv"
    `include "dma_wr_backpressure_test.sv"

    // Concurrency Tests (CONC)
    `include "dma_conc_nominal_test.sv"
    `include "dma_conc_identical_tag_test.sv"
    `include "dma_conc_adjacent_addr_test.sv"
    `include "dma_conc_backpressure_test.sv"

endpackage : dma_test_pkg

`endif // DMA_TEST_PKG_SV
