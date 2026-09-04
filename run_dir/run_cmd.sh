#!/bin/bash
# ===============================================================================
# File:        run_cmd.sh
# Description: Cadence Xcelium Test Runner driven by testlist.f
#
# Usage:
#   ./run_cmd.sh                          (Runs default active test from testlist.f)
#   ./run_cmd.sh <test_name>              (Runs specific test, e.g. ./run_cmd.sh axi_sanity_test)
#   ./run_cmd.sh <test_name> -gui         (Runs specific test with SimVision GUI)
#   ./run_cmd.sh <test_name> -cov         (Runs with functional/code coverage collection)
#   ./run_cmd.sh -report [test_name]      (Generates HTML coverage report using Cadence IMC)
#   ./run_cmd.sh -list                    (Lists all tests registered in testlist.f)
#   ./run_cmd.sh -all                     (Runs ALL active tests in testlist.f)
#   ./run_cmd.sh -clean                   (Cleans work libraries, logs, and coverage)
# ===============================================================================

TESTLIST_FILE="testlist.f"
WAVES_TCL="waves.tcl"
FILELIST="filelist.f"

MODE="ram"
TEST=""
GUI=""
COV=""
GEN_REPORT=0
VERBOSITY="UVM_MEDIUM"
SEED="random"
RUN_ALL=0
EXTRA_ARGS=""

# 1. Read and parse active tests from testlist.f (ignoring comments and empty lines)
ACTIVE_TESTS=()
if [[ -f "$TESTLIST_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim leading/trailing whitespace
        trimmed=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        # Ignore comments and empty lines
        if [[ -n "$trimmed" && ! "$trimmed" =~ ^# ]]; then
            ACTIVE_TESTS+=("$trimmed")
        fi
    done < "$TESTLIST_FILE"
fi

# Function to list registered tests
list_tests() {
    echo "==============================================================================="
    echo " Registered Tests in $TESTLIST_FILE:"
    echo "==============================================================================="
    if [[ ${#ACTIVE_TESTS[@]} -eq 0 ]]; then
        echo " (No active tests found in $TESTLIST_FILE)"
    else
        for t in "${ACTIVE_TESTS[@]}"; do
            echo "   • $t"
        done
    fi
    echo "==============================================================================="
    exit 0
}

# Function to generate HTML Coverage report using Cadence IMC
generate_coverage_report() {
    local target_test="$1"
    if [[ -z "$target_test" ]]; then
        if [[ ${#ACTIVE_TESTS[@]} -gt 0 ]]; then
            target_test="${ACTIVE_TESTS[0]}"
        else
            target_test="axi_sanity_test"
        fi
    fi

    echo "==============================================================================="
    echo " [GENERATING COVERAGE REPORTS] : Target Test '$target_test'"
    echo "==============================================================================="

    if [[ ! -d "cov_work" ]]; then
        echo "[ERROR] 'cov_work' directory not found. Please run tests with '-cov' flag first:"
        echo "        ./run_cmd.sh $target_test -cov"
        exit 1
    fi

    mkdir -p cov_html_report
    echo "[INFO] Invoking Cadence IMC (Integrated Metrics Center) in batch mode..."
    
    imc -load cov_work/scope/$target_test -execcmd "\
        report -summary -out cov_report.txt -metrics all; \
        report -detail -out cov_detailed_report.txt -metrics all -all; \
        report -html -out cov_html_report -detail -metrics all"

    echo ""
    echo "==============================================================================="
    echo " [SUCCESS] Coverage Reports Generated:"
    echo "   1. Summary Report  : cov_report.txt"
    echo "   2. Detailed Report : cov_detailed_report.txt (Bin-level breakdown)"
    echo "   3. HTML Report     : cov_html_report/index.html"
    echo "==============================================================================="
    exit 0
}

# Parse positional argument if first argument is a test name (does not start with '-')
if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
    TEST="$1"
    shift
fi

# Parse flags
while [[ $# -gt 0 ]]; do
    case $1 in
        -test)
            TEST="$2"
            shift 2
            ;;
        -mode)
            MODE="$2"
            shift 2
            ;;
        -gui)
            GUI="-gui -linedebug"
            shift
            ;;
        -cov|-coverage)
            COV="ENABLE"
            shift
            ;;
        -report|-html)
            GEN_REPORT=1
            shift
            ;;
        -verb|-verbosity)
            VERBOSITY="$2"
            shift 2
            ;;
        -seed)
            SEED="$2"
            shift 2
            ;;
        -all)
            RUN_ALL=1
            shift
            ;;
        -list|-l)
            list_tests
            ;;
        -clean)
            echo "[INFO] Cleaning previous simulation and coverage artifacts..."
            rm -rf xcelium.d xrun.* waves.shm *.vcd *.log *.key .simvision INCA_libs .bpad logs/ cov_work/ cov_html_report/ imc.log imc.key
            exit 0
            ;;
        -help|-h)
            echo "==============================================================================="
            echo " AXI4 VIP Test Runner (Driven by $TESTLIST_FILE)"
            echo "==============================================================================="
            echo " Usage:"
            echo "   ./run_cmd.sh [test_name] [options]"
            echo ""
            echo " Options:"
            echo "   ./run_cmd.sh                      Run default test from $TESTLIST_FILE"
            echo "   ./run_cmd.sh <test_name>          Run specific test"
            echo "   ./run_cmd.sh <test_name> -gui     Run with SimVision Waveform GUI"
            echo "   ./run_cmd.sh <test_name> -cov     Run with Functional Coverage enabled"
            echo "   ./run_cmd.sh -report [test_name]  Generate HTML coverage report via IMC"
            echo "   ./run_cmd.sh -all                 Run all active tests in $TESTLIST_FILE"
            echo "   ./run_cmd.sh -list                List registered tests in $TESTLIST_FILE"
            echo "   ./run_cmd.sh -clean               Clean simulation logs and databases"
            echo "==============================================================================="
            exit 0
            ;;
        *)
            if [[ ! "$1" =~ ^- ]]; then
                TEST="$1"
            else
                EXTRA_ARGS="$EXTRA_ARGS $1"
            fi
            shift
            ;;
    esac
done

# If report generation flag was passed, run report generator directly
if [[ $GEN_REPORT -eq 1 ]]; then
    generate_coverage_report "$TEST"
fi

mkdir -p logs

# Set topology define macro
case $MODE in
    ram|RAM)
        DEFINE_MACRO="+define+RAM_STANDALONE"
        ;;
    dma|DMA)
        DEFINE_MACRO="+define+DMA_STANDALONE"
        ;;
    sys|SYS|subsystem)
        DEFINE_MACRO="+define+SUBSYSTEM"
        ;;
    *)
        echo "[ERROR] Unknown mode '$MODE'. Use -mode ram, -mode dma, or -mode sys."
        exit 1
        ;;
esac

# Check for waves.tcl
INPUT_TCL=""
if [[ -f "$WAVES_TCL" && -z "$GUI" ]]; then
    INPUT_TCL="-input $WAVES_TCL"
fi

# Function to run a single test
run_single_test() {
    local t_name="$1"
    local log_file="logs/sim_${MODE}_${t_name}.log"

    echo "==============================================================================="
    echo " [RUNNING TEST] : $t_name  (Mode: $MODE)"
    echo "==============================================================================="

    local cov_flags=""
    if [[ "$COV" == "ENABLE" ]]; then
        cov_flags="-coverage all -covoverwrite -covworkdir ./cov_work -covtest $t_name"
        echo "[INFO] Coverage collection enabled (Target: ./cov_work/scope/$t_name)"
    fi

    local cmd="xrun -64bit -sv -uvm \
         -timescale 1ns/1ns \
         -access +rwc \
         -svseed $SEED \
         $DEFINE_MACRO \
         +UVM_TESTNAME=$t_name \
         +UVM_VERBOSITY=$VERBOSITY \
         $INPUT_TCL \
         -f $FILELIST \
         -l $log_file \
         $cov_flags \
         $GUI \
         $EXTRA_ARGS"

    echo "[COMMAND] $cmd"
    echo ""

    eval $cmd
}

# Main Execution Flow
if [[ $RUN_ALL -eq 1 ]]; then
    if [[ ${#ACTIVE_TESTS[@]} -eq 0 ]]; then
        echo "[ERROR] No active tests found in $TESTLIST_FILE to run."
        exit 1
    fi
    echo ">>> Running all ${#ACTIVE_TESTS[@]} test(s) from $TESTLIST_FILE..."
    for t in "${ACTIVE_TESTS[@]}"; do
        run_single_test "$t"
    done
else
    # If no test specified, take the first test from testlist.f
    if [[ -z "$TEST" ]]; then
        if [[ ${#ACTIVE_TESTS[@]} -gt 0 ]]; then
            TEST="${ACTIVE_TESTS[0]}"
            echo "[INFO] No test specified. Using default active test from $TESTLIST_FILE: '$TEST'"
        else
            echo "[ERROR] No test specified and $TESTLIST_FILE is empty."
            exit 1
        fi
    fi

    run_single_test "$TEST"
fi
