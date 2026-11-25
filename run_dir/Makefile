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
              -top tb_top \
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
        run_dma gui_dma \
        run_all_mm2s merge_cov_mm2s gui_cov_mm2s regr_mm2s \
        run_all_s2mm merge_cov_s2mm gui_cov_s2mm regr_s2mm \
        run_all_conc merge_cov_conc gui_cov_conc regr_conc \
        run_all_dma merge_cov gui_cov regr_all_dma \
        run_ram gui_ram waves_ram \
        run_sys gui_sys \
        report_cov imc_gui

# -------------------------------------------------------------------------------
# 3. Help Menu
# -------------------------------------------------------------------------------
help:
	@echo "==============================================================================="
	@echo " AXI4 VIP Cadence Xcelium Simulation Makefile"
	@echo "==============================================================================="
	@echo " 1. HARDWARE BINDING CHECKS:"
	@echo "    make test_dma                  : Test Standalone DMA elaboration"
	@echo "    make test_ram                  : Test Standalone RAM elaboration"
	@echo "    make test_sys                  : Test Full Subsystem elaboration"
	@echo "    make test_all                  : Test all 3 topologies sequentially"
	@echo ""
	@echo " 2. TEST EXECUTION (Coverage is ALWAYS collected into ./cov_work):"
	@echo "    make run_dma [TEST=<name>]     : Run single DMA test (default: dma_sanity_test)"
	@echo "    make gui_dma [TEST=<name>]     : Run single DMA test with SimVision GUI"
	@echo "    make run_all_mm2s              : Run all 6 MM2S tests + terminal summary"
	@echo "    make run_all_s2mm              : Run all 11 S2MM tests + terminal summary"
	@echo "    make run_all_conc              : Run all 4 Concurrency tests + terminal summary"
	@echo "    make run_all_dma               : Run all 21 DMA feature tests (MM2S+S2MM+CONC) + summary"
	@echo "    make run_sys [TEST=<name>]     : Run Subsystem test (default: dma_sanity_test)"
	@echo "    make run_ram [TEST=<name>]     : Run RAM test (default: axi_sanity_test)"
	@echo "    make waves_ram                 : Open generated waves.shm in Cadence SimVision"
	@echo ""
	@echo " 3. COVERAGE REPORTING & MERGING (Cadence IMC):"
	@echo "    make merge_cov                 : Merge ALL tests (MM2S + S2MM + CONC) into $(MERGED_ALL_DIR)"
	@echo "    make gui_cov                   : Open Cadence IMC GUI with Unified Merged DB ($(MERGED_ALL_DIR))"
	@echo "    make regr_all_dma              : Full Regression (run_all_dma + merge_cov)"
	@echo "    make merge_cov_conc            : Merge all Concurrency test coverage databases"
	@echo "    make gui_cov_conc              : Open Cadence IMC GUI with Concurrency Merged DB"
	@echo "    make regr_conc                 : Run all Concurrency tests + auto-merge coverage + reports"
	@echo "    make merge_cov_s2mm            : Merge all S2MM test coverage databases"
	@echo "    make gui_cov_s2mm              : Open Cadence IMC GUI with S2MM Merged DB"
	@echo "    make regr_s2mm                 : Run all S2MM tests + auto-merge coverage + reports"
	@echo "    make merge_cov_mm2s            : Merge all MM2S test coverage databases"
	@echo "    make gui_cov_mm2s              : Open Cadence IMC GUI with MM2S Merged DB"
	@echo "    make regr_mm2s                 : Run all MM2S tests + auto-merge coverage + reports"
	@echo "    make report_cov [TEST=<name>]  : Generate Text & HTML Coverage Reports for single test"
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
	$(XRUN_BASE) +define+RAM_STANDALONE -covdut axi_ram +UVM_TESTNAME=$(TEST) -covtest $(TEST) -l $(LOG_DIR)/sim_ram_$(TEST).log

run_dma: setup
	@$(eval DMA_TEST := $(if $(filter axi_sanity_test,$(TEST)),dma_sanity_test,$(TEST)))
	@echo "[XCELIUM] Running DMA Standalone Test with Full Coverage: $(DMA_TEST)"
	$(XRUN_BASE) +define+DMA_STANDALONE -covdut axi_dma +UVM_TESTNAME=$(DMA_TEST) -covtest $(DMA_TEST) -l $(LOG_DIR)/sim_dma_$(DMA_TEST).log

run_sys: setup
	@$(eval SYS_TARGET_TEST := $(if $(filter axi_sanity_test,$(TEST)),dma_sanity_test,$(TEST)))
	@echo "[XCELIUM] Running Subsystem Test with Full Coverage: $(SYS_TARGET_TEST)"
	$(XRUN_BASE) +define+SUBSYSTEM +UVM_TESTNAME=$(SYS_TARGET_TEST) -covtest $(SYS_TARGET_TEST) -l $(LOG_DIR)/sim_sys_$(SYS_TARGET_TEST).log

# MM2S Feature Regression Suite (6 Feature Tests)
MM2S_TESTS := dma_rd_nominal_test \
              dma_rd_multiburst_test \
              dma_rd_4kb_split_test \
              dma_rd_unaligned_test \
              dma_rd_partial_len_test \
              dma_rd_backpressure_test

# S2MM Feature Regression Suite (11 Feature Tests)
S2MM_TESTS := dma_wr_nominal_test \
              dma_wr_b2b_test \
              dma_wr_multiburst_test \
              dma_wr_4kb_split_test \
              dma_wr_unaligned_test \
              dma_wr_partial_len_test \
              dma_wr_early_term_test \
              dma_wr_excess_data_test \
              dma_wr_skew_test \
              dma_wr_stream_bubble_test \
              dma_wr_backpressure_test

# Concurrency Feature Regression Suite (4 Feature Tests)
CONC_TESTS := dma_conc_nominal_test \
              dma_conc_identical_tag_test \
              dma_conc_adjacent_addr_test \
              dma_conc_backpressure_test

# Complete DMA Feature Regression Suite (MM2S + S2MM + CONC = 21 Feature Tests)
ALL_DMA_TESTS := $(MM2S_TESTS) \
                 $(S2MM_TESTS) \
                 $(CONC_TESTS)

MERGED_MM2S_DIR := merged_mm2s
MERGED_S2MM_DIR := merged_s2mm
MERGED_CONC_DIR := merged_conc
MERGED_ALL_DIR  := merged_dma
MERGED_DIR      ?= $(MERGED_ALL_DIR)

# -------------------------------------------------------------------------------
# MM2S Regression & Coverage Targets
# -------------------------------------------------------------------------------
run_all_mm2s: setup
	@echo "==============================================================================="
	@echo " [REGRESSION] Executing All MM2S Test Cases Sequentially with Full Coverage"
	@echo "==============================================================================="
	@for t in $(MM2S_TESTS); do \
		echo ""; \
		echo ">>> [RUNNING TEST]: $$t ..."; \
		$(MAKE) run_dma TEST=$$t GUI=0 || true; \
	done
	@echo ""
	@echo "==============================================================================="
	@echo "                 MM2S REGRESSION TEST RESULTS SUMMARY                         "
	@echo "==============================================================================="
	@total=0; pass=0; fail=0; \
	for t in $(MM2S_TESTS); do \
		total=$$((total + 1)); \
		log_file="$(LOG_DIR)/sim_dma_$${t}.log"; \
		if [ -f "$$log_file" ] && grep -q "UVM_ERROR : *0" "$$log_file" && grep -q "UVM_FATAL : *0" "$$log_file"; then \
			printf "  %-32s : [PASSED]\n" "$$t"; \
			pass=$$((pass + 1)); \
		else \
			printf "  %-32s : [FAILED] (see $$log_file)\n" "$$t"; \
			fail=$$((fail + 1)); \
		fi; \
	done; \
	echo "==============================================================================="; \
	echo " Total Tests: $$total | Passed: $$pass | Failed: $$fail"; \
	echo "==============================================================================="; \
	if [ $$fail -ne 0 ]; then \
		echo ">>> [REGRESSION FAILED] $$fail MM2S test(s) failed or did not run."; \
		exit 1; \
	else \
		echo ">>> [REGRESSION PASSED] All $$pass MM2S tests completed with ZERO UVM errors!"; \
	fi

merge_cov_mm2s:
	@echo "==============================================================================="
	@echo " [IMC] Merging Coverage Across All MM2S Tests into $(MERGED_MM2S_DIR)"
	@echo "==============================================================================="
	@mkdir -p cov_html_report_mm2s
	$(IMC_CMD) -execcmd "\
		merge -out $(MERGED_MM2S_DIR) $(foreach t,$(MM2S_TESTS),cov_work/scope/$(t)); \
		load cov_work/scope/$(MERGED_MM2S_DIR); \
		report -summary -out cov_mm2s_summary.txt -metrics all; \
		report -detail -out cov_mm2s_detail.txt -metrics all -all; \
		report -html -out cov_html_report_mm2s -detail -metrics all"
	@echo "==============================================================================="
	@echo ">>> 1. MM2S Merged Coverage DB  : cov_work/scope/$(MERGED_MM2S_DIR)"
	@echo ">>> 2. Summary Text Report      : cov_mm2s_summary.txt"
	@echo ">>> 3. Detailed Text Report     : cov_mm2s_detail.txt"
	@echo ">>> 4. Interactive HTML Report  : cov_html_report_mm2s/index.html"
	@echo "==============================================================================="

gui_cov_mm2s:
	@echo "[IMC] Launching Cadence IMC GUI with MM2S Merged Database: $(MERGED_MM2S_DIR)..."
	$(IMC_CMD) -load cov_work/scope/$(MERGED_MM2S_DIR) &

regr_mm2s: run_all_mm2s merge_cov_mm2s

# -------------------------------------------------------------------------------
# S2MM Regression & Coverage Targets
# -------------------------------------------------------------------------------
run_all_s2mm: setup
	@echo "==============================================================================="
	@echo " [REGRESSION] Executing All S2MM Test Cases Sequentially with Full Coverage"
	@echo "==============================================================================="
	@for t in $(S2MM_TESTS); do \
		echo ""; \
		echo ">>> [RUNNING TEST]: $$t ..."; \
		$(MAKE) run_dma TEST=$$t GUI=0 || true; \
	done
	@echo ""
	@echo "==============================================================================="
	@echo "                 S2MM REGRESSION TEST RESULTS SUMMARY                         "
	@echo "==============================================================================="
	@total=0; pass=0; fail=0; \
	for t in $(S2MM_TESTS); do \
		total=$$((total + 1)); \
		log_file="$(LOG_DIR)/sim_dma_$${t}.log"; \
		if [ -f "$$log_file" ] && grep -q "UVM_ERROR : *0" "$$log_file" && grep -q "UVM_FATAL : *0" "$$log_file"; then \
			printf "  %-32s : [PASSED]\n" "$$t"; \
			pass=$$((pass + 1)); \
		else \
			printf "  %-32s : [FAILED] (see $$log_file)\n" "$$t"; \
			fail=$$((fail + 1)); \
		fi; \
	done; \
	echo "==============================================================================="; \
	echo " Total Tests: $$total | Passed: $$pass | Failed: $$fail"; \
	echo "==============================================================================="; \
	if [ $$fail -ne 0 ]; then \
		echo ">>> [REGRESSION FAILED] $$fail S2MM test(s) failed or did not run."; \
		exit 1; \
	else \
		echo ">>> [REGRESSION PASSED] All $$pass S2MM tests completed with ZERO UVM errors!"; \
	fi

merge_cov_s2mm:
	@echo "==============================================================================="
	@echo " [IMC] Merging Coverage Across All S2MM Tests into $(MERGED_S2MM_DIR)"
	@echo "==============================================================================="
	@mkdir -p cov_html_report_s2mm
	$(IMC_CMD) -execcmd "\
		merge -out $(MERGED_S2MM_DIR) $(foreach t,$(S2MM_TESTS),cov_work/scope/$(t)); \
		load cov_work/scope/$(MERGED_S2MM_DIR); \
		report -summary -out cov_s2mm_summary.txt -metrics all; \
		report -detail -out cov_s2mm_detail.txt -metrics all -all; \
		report -html -out cov_html_report_s2mm -detail -metrics all"
	@echo "==============================================================================="
	@echo ">>> 1. S2MM Merged Coverage DB  : cov_work/scope/$(MERGED_S2MM_DIR)"
	@echo ">>> 2. Summary Text Report      : cov_s2mm_summary.txt"
	@echo ">>> 3. Detailed Text Report     : cov_s2mm_detail.txt"
	@echo ">>> 4. Interactive HTML Report  : cov_html_report_s2mm/index.html"
	@echo "==============================================================================="

gui_cov_s2mm:
	@echo "[IMC] Launching Cadence IMC GUI with S2MM Merged Database: $(MERGED_S2MM_DIR)..."
	$(IMC_CMD) -load cov_work/scope/$(MERGED_S2MM_DIR) &

regr_s2mm: run_all_s2mm merge_cov_s2mm

# -------------------------------------------------------------------------------
# Concurrency Regression & Coverage Targets (4 Feature Tests)
# -------------------------------------------------------------------------------
run_all_conc: setup
	@echo "==============================================================================="
	@echo " [REGRESSION] Executing All Concurrency Test Cases Sequentially with Full Coverage"
	@echo "==============================================================================="
	@for t in $(CONC_TESTS); do \
		echo ""; \
		echo ">>> [RUNNING TEST]: $$t ..."; \
		$(MAKE) run_dma TEST=$$t GUI=0 || true; \
	done
	@echo ""
	@echo "==============================================================================="
	@echo "             CONCURRENCY REGRESSION TEST RESULTS SUMMARY                       "
	@echo "==============================================================================="
	@total=0; pass=0; fail=0; \
	for t in $(CONC_TESTS); do \
		total=$$((total + 1)); \
		log_file="$(LOG_DIR)/sim_dma_$${t}.log"; \
		if [ -f "$$log_file" ] && grep -q "UVM_ERROR : *0" "$$log_file" && grep -q "UVM_FATAL : *0" "$$log_file"; then \
			printf "  %-32s : [PASSED]\n" "$$t"; \
			pass=$$((pass + 1)); \
		else \
			printf "  %-32s : [FAILED] (see $$log_file)\n" "$$t"; \
			fail=$$((fail + 1)); \
		fi; \
	done; \
	echo "==============================================================================="; \
	echo " Total Tests: $$total | Passed: $$pass | Failed: $$fail"; \
	echo "==============================================================================="; \
	if [ $$fail -ne 0 ]; then \
		echo ">>> [REGRESSION FAILED] $$fail Concurrency test(s) failed or did not run."; \
		exit 1; \
	else \
		echo ">>> [REGRESSION PASSED] All $$pass Concurrency tests completed with ZERO UVM errors!"; \
	fi

merge_cov_conc:
	@echo "==============================================================================="
	@echo " [IMC] Merging Coverage Across All Concurrency Tests into $(MERGED_CONC_DIR)"
	@echo "==============================================================================="
	@mkdir -p cov_html_report_conc
	$(IMC_CMD) -execcmd "\
		merge -out $(MERGED_CONC_DIR) $(foreach t,$(CONC_TESTS),cov_work/scope/$(t)); \
		load cov_work/scope/$(MERGED_CONC_DIR); \
		report -summary -out cov_conc_summary.txt -metrics all; \
		report -detail -out cov_conc_detail.txt -metrics all -all; \
		report -html -out cov_html_report_conc -detail -metrics all"
	@echo "==============================================================================="
	@echo ">>> 1. Concurrency Merged Coverage DB : cov_work/scope/$(MERGED_CONC_DIR)"
	@echo ">>> 2. Summary Text Report            : cov_conc_summary.txt"
	@echo ">>> 3. Detailed Text Report           : cov_conc_detail.txt"
	@echo ">>> 4. Interactive HTML Report        : cov_html_report_conc/index.html"
	@echo "==============================================================================="

gui_cov_conc:
	@echo "[IMC] Launching Cadence IMC GUI with Concurrency Merged Database: $(MERGED_CONC_DIR)..."
	$(IMC_CMD) -load cov_work/scope/$(MERGED_CONC_DIR) &

regr_conc: run_all_conc merge_cov_conc

# -------------------------------------------------------------------------------
# Full Unified DMA Feature Regression & Coverage Targets (MM2S + S2MM + CONC = 21 Tests)
# -------------------------------------------------------------------------------
run_all_dma: setup
	@echo "==============================================================================="
	@echo " [REGRESSION] Executing Full DMA Feature Regression (MM2S + S2MM + CONC = 21 Tests)"
	@echo "==============================================================================="
	@for t in $(ALL_DMA_TESTS); do \
		echo ""; \
		echo ">>> [RUNNING TEST]: $$t ..."; \
		$(MAKE) run_dma TEST=$$t GUI=0 || true; \
	done
	@echo ""
	@echo "==============================================================================="
	@echo "                 DMA FULL REGRESSION TEST RESULTS SUMMARY                     "
	@echo "==============================================================================="
	@total=0; pass=0; fail=0; \
	for t in $(ALL_DMA_TESTS); do \
		total=$$((total + 1)); \
		log_file="$(LOG_DIR)/sim_dma_$${t}.log"; \
		if [ -f "$$log_file" ] && grep -q "UVM_ERROR : *0" "$$log_file" && grep -q "UVM_FATAL : *0" "$$log_file"; then \
			printf "  %-32s : [PASSED]\n" "$$t"; \
			pass=$$((pass + 1)); \
		else \
			printf "  %-32s : [FAILED] (see $$log_file)\n" "$$t"; \
			fail=$$((fail + 1)); \
		fi; \
	done; \
	echo "==============================================================================="; \
	echo " Total Tests: $$total | Passed: $$pass | Failed: $$fail"; \
	echo "==============================================================================="; \
	if [ $$fail -ne 0 ]; then \
		echo ">>> [REGRESSION FAILED] $$fail DMA test(s) failed or did not run."; \
		exit 1; \
	else \
		echo ">>> [REGRESSION PASSED] All $$pass DMA tests completed with ZERO UVM errors!"; \
	fi

merge_cov:
	@echo "==============================================================================="
	@echo " [IMC] Merging Unified Coverage Across ALL Tests (MM2S + S2MM + CONC) into $(MERGED_ALL_DIR)"
	@echo "==============================================================================="
	@mkdir -p cov_html_report
	$(IMC_CMD) -execcmd "\
		merge -out $(MERGED_ALL_DIR) $(foreach t,$(ALL_DMA_TESTS),cov_work/scope/$(t)); \
		load cov_work/scope/$(MERGED_ALL_DIR); \
		report -summary -out cov_merged_summary.txt -metrics all; \
		report -detail -out cov_merged_detail.txt -metrics all -all; \
		report -html -out cov_html_report -detail -metrics all"
	@echo "==============================================================================="
	@echo ">>> 1. Unified Merged Database : cov_work/scope/$(MERGED_ALL_DIR)"
	@echo ">>> 2. Summary Text Report     : cov_merged_summary.txt"
	@echo ">>> 3. Detailed Text Report    : cov_merged_detail.txt"
	@echo ">>> 4. Interactive HTML Report : cov_html_report/index.html"
	@echo "==============================================================================="

gui_cov:
	@echo "[IMC] Launching Cadence IMC GUI with Unified Merged Database: $(MERGED_DIR)..."
	$(IMC_CMD) -load cov_work/scope/$(MERGED_DIR) &

regr_all_dma: run_all_dma merge_cov

# -------------------------------------------------------------------------------
# Interactive GUI & Utility Targets
# -------------------------------------------------------------------------------
gui_dma:
	$(MAKE) run_dma TEST=$(TEST) GUI=1

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
# Clean Target
# -------------------------------------------------------------------------------
clean:
	@echo "[CLEAN] Removing simulation temporary files, logs, and databases..."
	rm -rf xcelium.d xrun.* waves.shm *.vcd *.log *.key .simvision INCA_libs .bpad $(LOG_DIR) cov_work/ cov_html_report/ cov_html_report_s2mm/ cov_html_report_mm2s/ cov_html_report_conc/ imc.log imc.key cov_merged_summary.txt cov_merged_detail.txt cov_s2mm_summary.txt cov_s2mm_detail.txt cov_mm2s_summary.txt cov_mm2s_detail.txt cov_conc_summary.txt cov_conc_detail.txt cov_report.txt cov_detailed_report.txt
