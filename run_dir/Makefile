# ===============================================================================
# File:        Makefile
# Description: Cadence Xcelium Simulation Makefile for AXI4 VIP Project
# Author:      Akshansh Chaurasia
# Tool:        Cadence Xcelium (xrun) & SimVision (GUI)
# ===============================================================================

# -------------------------------------------------------------------------------
# 1. Configurable Parameters & Defaults
# -------------------------------------------------------------------------------
TEST       ?= axi_sanity_test
SEED       ?= random
VERB       ?= UVM_MEDIUM
GUI        ?= 0
FILELIST   := filelist.f
LOG_DIR    := logs

# Base Xcelium Command
XRUN_BASE  := xrun -64bit -sv -uvm \
              -timescale 1ns/1ns \
              -access +rwc \
              -svseed $(SEED) \
              +UVM_TESTNAME=$(TEST) \
              +UVM_VERBOSITY=$(VERB) \
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
        run_ram gui_ram

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
	@echo " 2. TEST EXECUTION (RAM Verification):"
	@echo "    make run_ram [TEST=<name>]     : Run test in batch mode (dumps waves.shm)"
	@echo "    make waves_ram                 : Open generated waves.shm in Cadence SimVision"
	@echo "    make gui_ram [TEST=<name>]     : Run test with interactive SimVision GUI"
	@echo ""
	@echo " 3. UTILITIES:"
	@echo "    make clean                     : Remove simulation logs, work libraries, and dumps"
	@echo "==============================================================================="

setup:
	@mkdir -p $(LOG_DIR)

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
# 5. Test Execution (RAM Standalone Mode)
# -------------------------------------------------------------------------------
run_ram: setup
	@echo "[XCELIUM] Running RAM Test: $(TEST)"
	$(XRUN_BASE) +define+RAM_STANDALONE -l $(LOG_DIR)/sim_ram_$(TEST).log

gui_ram:
	$(MAKE) run_ram TEST=$(TEST) GUI=1

# Run with Functional/Code Coverage
cov_ram: setup
	@echo "[XCELIUM] Running RAM Test with Coverage: $(TEST)"
	$(XRUN_BASE) +define+RAM_STANDALONE -coverage all -covoverwrite -covworkdir ./cov_work -covtest $(TEST) -l $(LOG_DIR)/sim_ram_$(TEST)_cov.log

# Generate Text and HTML Coverage Reports using Cadence IMC
report_cov:
	@echo "[IMC] Generating Summary and Detailed Coverage Reports..."
	@mkdir -p cov_html_report
	imc -load cov_work/scope/$(TEST) -execcmd "\
	    report -summary -out cov_report.txt -metrics all; \
	    report -detail -out cov_detailed_report.txt -metrics all -all; \
	    report -html -out cov_html_report -detail -metrics all"
	@echo "==============================================================================="
	@echo ">>> 1. Summary Report  : cov_report.txt"
	@echo ">>> 2. Detailed Report : cov_detailed_report.txt (Bin-level hit/miss breakdown)"
	@echo ">>> 3. HTML Report     : cov_html_report/index.html"
	@echo "==============================================================================="

# -------------------------------------------------------------------------------
# 6. Clean Target
# -------------------------------------------------------------------------------
clean:
	@echo "[CLEAN] Removing simulation temporary files, logs, and databases..."
	rm -rf xcelium.d xrun.* waves.shm *.vcd *.log *.key .simvision INCA_libs .bpad $(LOG_DIR) cov_work/ cov_html_report/ imc.log imc.key
