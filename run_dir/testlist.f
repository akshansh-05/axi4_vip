# ===============================================================================
# File:        testlist.f
# Description: Test Registry for AXI4 VIP Project
# Each line defines a test case. Comments (#) and empty lines are ignored.
# ===============================================================================

# 1. DMA Standalone Tests (DMA_STANDALONE) - Primary Target
dma_sanity_test
dma_base_test
dma_rd_nominal_test
dma_rd_multiburst_test
dma_rd_4kb_split_test
dma_rd_unaligned_test
dma_rd_partial_len_test
dma_rd_backpressure_test

# 2. SRAM Standalone Tests (RAM_STANDALONE)
sram_base_test
axi_sanity_test
