# ===============================================================================
# File:        Makefile
# Description: Cadence Xcelium Simulation Makefile for AXI4 VIP Project
# Author:      Akshansh Chaurasia
# Tool:        Cadence Xcelium (xrun) & SimVision (GUI)
# ===============================================================================

# -------------------------------------------------------------------------------
# 1. Configurable Parameters & Defaults
# -------------------------------------------------------------------------------
TEST       ?= dma_sanity_test
SEED       ?= random
VERB       ?= UVM_MEDIUM
GUI        ?= 0
FILELIST   := filelist.f
LOG_DIR    := logs
COV_DIR    := ./cov_work

# Base Xcelium Command (Coverage is ALWAYS enabled for all test runs)
XRUN_BASE  := xrun -64bit -sv -uvm \
              -timescale 1ns/1ns \
              -access +rwc \
              -svseed $(SEED) \
              +UVM_TESTNAME=$(TEST) \
              +UVM_VERBOSITY=$(VERB) \
              -coverage all \
              -covoverwrite \
              -covworkdir $(COV_DIR) \
              -input waves.tcl \
              -f $(FILELIST)

ifeq ($(GUI), 1)
    XRUN_BASE += -gui -linedebug
endif

# -------------------------------------------------------------------------------
# 2. Phony Targets
# -------------------------------------------------------------------------------
.PHONY: help setup clean \
        test_ram test_dma test_sys test_all \
        run_ram gui_ram waves_ram \
        run_dma run_sys gui_sys \
        report_cov imc_gui

# -------------------------------------------------------------------------------
# 3. Help Menu
# -------------------------------------------------------------------------------
help:
	@echo "==============================================================================="
	@echo " AXI4 VIP Cadence Xcelium Simulation Makefile"
	@echo "==============================================================================="
	@echo " 1. HARDWARE BINDING CHECKS:"
	@echo "    make test_ram                  : Test Standalone RAM elaboration"
	@echo "    make test_dma                  : Test Standalone DMA elaboration"
	@echo "    make test_sys                  : Test Full Subsystem elaboration"
	@echo "    make test_all                  : Test all 3 topologies sequentially"
	@echo ""
	@echo " 2. TEST EXECUTION (Coverage is ALWAYS collected into ./cov_work):"
	@echo "    make run_sys [TEST=<name>]     : Run Subsystem test (default: dma_sanity_test)"
	@echo "    make run_dma [TEST=<name>]     : Run DMA test (default: dma_sanity_test)"
	@echo "    make run_ram [TEST=<name>]     : Run RAM test (default: axi_sanity_test)"
	@echo "    make gui_sys [TEST=<name>]     : Run Subsystem test with interactive SimVision GUI"
	@echo "    make waves_ram                 : Open generated waves.shm in Cadence SimVision"
	@echo ""
	@echo " 3. COVERAGE REPORTING (Cadence IMC):"
	@echo "    make report_cov [TEST=<name>]  : Generate Text & HTML Coverage Reports"
	@echo "    make imc_gui [TEST=<name>]     : Launch Cadence IMC GUI to inspect coverage database"
	@echo ""
	@echo " 4. UTILITIES:"
	@echo "    make clean                     : Remove simulation logs, work libraries, and dumps"
	@echo "==============================================================================="

setup:
	@mkdir -p $(LOG_DIR)
	@if [ ! -d "../rtl" ] && [ -d "../../axi4_rtl" ]; then \
		echo "[INFO] Auto-linking ../../axi4_rtl to ../rtl"; \
		ln -sf ../../axi4_rtl ../rtl; \
	fi

# -------------------------------------------------------------------------------
# 4. Hardware Topology Elaboration Checks
# -------------------------------------------------------------------------------
test_ram: setup
	@echo "[XCELIUM] Testing RAM Standalone Hardware Binding..."
	xrun -64bit -sv -uvm -timescale 1ns/1ns -access +rwc +define+RAM_STANDALONE -f $(FILELIST) -l $(LOG_DIR)/test_ram_bind.log

test_dma: setup
	@echo "[XCELIUM] Testing DMA Standalone Hardware Binding..."
	xrun -64bit -sv -uvm -timescale 1ns/1ns -access +rwc +define+DMA_STANDALONE -f $(FILELIST) -l $(LOG_DIR)/test_dma_bind.log

test_sys: setup
	@echo "[XCELIUM] Testing Subsystem Loopback Hardware Binding..."
	xrun -64bit -sv -uvm -timescale 1ns/1ns -access +rwc +define+SUBSYSTEM -f $(FILELIST) -l $(LOG_DIR)/test_sys_bind.log

test_all: test_ram test_dma test_sys
	@echo ">>> ALL 3 HARDWARE CONFIGURATIONS COMPILED & ELABORATED SUCCESSFULLY!"

# -------------------------------------------------------------------------------
# 5. Test Execution Targets (Coverage collection is active for all runs)
# -------------------------------------------------------------------------------
run_ram: setup
	@echo "[XCELIUM] Running RAM Test with Full Coverage: $(TEST)"
	$(XRUN_BASE) +define+RAM_STANDALONE +UVM_TESTNAME=$(TEST) -covtest $(TEST) -l $(LOG_DIR)/sim_ram_$(TEST).log

run_dma: setup
	@$(eval DMA_TEST := $(if $(filter axi_sanity_test,$(TEST)),dma_sanity_test,$(TEST)))
	@echo "[XCELIUM] Running DMA Standalone Test with Full Coverage: $(DMA_TEST)"
	$(XRUN_BASE) +define+DMA_STANDALONE +UVM_TESTNAME=$(DMA_TEST) -covtest $(DMA_TEST) -l $(LOG_DIR)/sim_dma_$(DMA_TEST).log

run_sys: setup
	@$(eval SYS_TARGET_TEST := $(if $(filter axi_sanity_test,$(TEST)),dma_sanity_test,$(TEST)))
	@echo "[XCELIUM] Running Subsystem Test with Full Coverage: $(SYS_TARGET_TEST)"
	$(XRUN_BASE) +define+SUBSYSTEM +UVM_TESTNAME=$(SYS_TARGET_TEST) -covtest $(SYS_TARGET_TEST) -l $(LOG_DIR)/sim_sys_$(SYS_TARGET_TEST).log

gui_ram:
	$(MAKE) run_ram TEST=$(TEST) GUI=1

gui_sys:
	$(MAKE) run_sys TEST=$(TEST) GUI=1

waves_ram:
	@echo "[SIMVISION] Opening waveforms..."
	simvision waves.shm &

# Clean environment override for VMANAGER2009 IMC (stripping old INCISIVE152 variables)
IMC_CMD := env -i HOME=$(HOME) USER=$(USER) DISPLAY=$(DISPLAY) \
               PATH=/home/installs/VMANAGER2009/bin:/home/installs/XCELIUM2009/bin:/home/installs/XCELIUM2009/tools/bin:/usr/bin:/bin \
               CDS_LIC_FILE=5280@14.139.1.126 \
               XCELIUMHOME=/home/installs/XCELIUM2009 \
               IUSHOME=/home/installs/XCELIUM2009 \
               CDS_INST_DIR=/home/installs/XCELIUM2009 \
               /home/installs/VMANAGER2009/bin/imc

# Generate Text and HTML Coverage Reports using Cadence IMC
report_cov:
	@echo "[IMC] Generating Summary and Detailed Coverage Reports using VMANAGER2009..."
	@mkdir -p cov_html_report
	$(IMC_CMD) -load cov_work/scope/$(TEST) -execcmd "\
	    report -summary -out cov_report.txt -metrics all; \
	    report -detail -out cov_detailed_report.txt -metrics all -all; \
	    report -html -out cov_html_report -detail -metrics all"
	@echo "==============================================================================="
	@echo ">>> 1. Summary Report  : cov_report.txt"
	@echo ">>> 2. Detailed Report : cov_detailed_report.txt (Bin-level hit/miss breakdown)"
	@echo ">>> 3. HTML Report     : cov_html_report/index.html"
	@echo "==============================================================================="

# Launch Cadence IMC GUI to inspect coverage graphically
imc_gui:
	@echo "[IMC] Launching Cadence IMC Coverage GUI for test: $(TEST)..."
	$(IMC_CMD) -load cov_work/scope/$(TEST) &

# -------------------------------------------------------------------------------
# 6. Clean Target
# -------------------------------------------------------------------------------
clean:
	@echo "[CLEAN] Removing simulation temporary files, logs, and databases..."
	rm -rf xcelium.d xrun.* waves.shm *.vcd *.log *.key .simvision INCA_libs .bpad $(LOG_DIR) cov_work/ cov_html_report/ imc.log imc.key

