# ===============================================================================
# File:        filelist.f
# Description: Unified Compilation Filelist for Cadence Xcelium (xrun)
# ===============================================================================

# 1. Include Search Paths (+incdir)
+incdir+../uvm
+incdir+../uvm/interfaces
+incdir+../uvm/vip/axi_mm_vip
+incdir+../uvm/vip/axis_vip
+incdir+../uvm/vip/dma_desc_vip
+incdir+../uvm/env
+incdir+../uvm/virtual_sequences
+incdir+../uvm/tests

# 2. RTL Design Files (DUT inside ../rtl/)
../rtl/axi_master_rtl/axi_dma_rd.v
../rtl/axi_master_rtl/axi_dma_wr.v
../rtl/axi_master_rtl/axi_dma.v
../rtl/axi_slave_rtl/axi_ram.v

# 3. SystemVerilog Interface Files
../uvm/interfaces/axi_if.sv
../uvm/interfaces/axis_if.sv
../uvm/interfaces/dma_desc_if.sv

# 4. UVM VIP & Environment Packages (In Dependency Order)
../uvm/tb_params_pkg.sv
../uvm/vip/axi_mm_vip/axi_mm_pkg.sv
../uvm/env/axi_env_pkg.sv
../uvm/tests/axi_test_pkg.sv

# 5. Top-Level Testbench Module
../uvm/tb_top.sv
