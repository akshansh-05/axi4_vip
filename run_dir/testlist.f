# ===============================================================================
# File:        testlist.f
# Description: Test Registry for AXI4 VIP Project
# Each line defines a test case. Comments (#) and empty lines are ignored.
# ===============================================================================

# 1. SRAM Standalone Tests (RAM_STANDALONE)
sram_base_test
axi_sanity_test

# 2. DMA Standalone & Subsystem Tests (DMA_STANDALONE & SUBSYSTEM)
dma_base_test
