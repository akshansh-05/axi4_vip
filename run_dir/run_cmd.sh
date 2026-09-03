#!/bin/bash
# ===============================================================================
# File:        run_cmd.sh
# Description: Cadence Xcelium Test Runner driven by testlist.f
#
# Usage:
#   ./run_cmd.sh                          (Runs default active test from testlist.f)
#   ./run_cmd.sh <test_name>              (Runs specific test, e.g. ./run_cmd.sh axi_sanity_test)
#   ./run_cmd.sh <test_name> -gui         (Runs specific test with SimVision GUI)
#   ./run_cmd.sh -list                    (Lists all tests registered in testlist.f)
#   ./run_cmd.sh -all                     (Runs ALL active tests in testlist.f)
#   ./run_cmd.sh -clean                   (Cleans work libraries and logs)
# ===============================================================================

TESTLIST_FILE="testlist.f"
WAVES_TCL="waves.tcl"
FILELIST="filelist.f"

MODE="ram"
TEST=""
GUI=""
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
            echo "[INFO] Cleaning previous simulation artifacts..."
            rm -rf xcelium.d xrun.* waves.shm *.vcd *.log *.key .simvision INCA_libs .bpad logs/
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
