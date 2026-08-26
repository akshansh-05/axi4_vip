#!/bin/bash
# ===============================================================================
# File:        run_cmd.sh
# Description: Cadence Xcelium Simulation Runner Script for AXI4 VIP Project
# Usage:
#   ./run_cmd.sh -mode ram -test ram_random_test
#   ./run_cmd.sh -mode dma -test dma_unaligned_test
#   ./run_cmd.sh -mode sys -test sys_loopback_test -gui
# ===============================================================================

# Default Options
MODE="sys"
TEST="base_test"
GUI=""
VERBOSITY="UVM_LOW"
SEED="random"
EXTRA_ARGS=""

# Help Function
print_help() {
    echo "==============================================================================="
    echo "AXI4 VIP Simulation Runner (Cadence Xcelium)"
    echo "==============================================================================="
    echo "Usage: ./run_cmd.sh [options]"
    echo ""
    echo "Options:"
    echo "  -mode <ram|dma|sys>    Select verification topology (Default: sys)"
    echo "                           ram -> Standalone AXI4 RAM (+define+RAM_STANDALONE)"
    echo "                           dma -> Standalone AXI4 DMA (+define+DMA_STANDALONE)"
    echo "                           sys -> Subsystem Loopback  (+define+SUBSYSTEM)"
    echo "  -test <test_name>      Specify UVM test name (Default: base_test)"
    echo "  -gui                   Open Cadence SimVision Waveform GUI"
    echo "  -verbosity <LEVEL>     UVM Verbosity (UVM_LOW, UVM_MEDIUM, UVM_HIGH, UVM_DEBUG)"
    echo "  -seed <SEED>           Random seed (Default: random or numeric value)"
    echo "  -clean                 Remove simulation logs and work libraries before run"
    echo "  -help                  Display this help message"
    echo "==============================================================================="
    exit 0
}

# Parse Command Line Arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -mode)
            MODE="$2"
            shift 2
            ;;
        -test)
            TEST="$2"
            shift 2
            ;;
        -gui)
            GUI="-gui -access +rwc"
            shift
            ;;
        -verbosity)
            VERBOSITY="$2"
            shift 2
            ;;
        -seed)
            SEED="$2"
            shift 2
            ;;
        -clean)
            echo "[INFO] Cleaning previous simulation artifacts..."
            rm -rf xcelium.d xrun.* waves.shm *.vcd *.log *.key .simvision INCA_libs
            shift
            ;;
        -help|-h)
            print_help
            ;;
        *)
            EXTRA_ARGS="$EXTRA_ARGS $1"
            shift
            ;;
    esac
done

# Map Mode to Compiler Macro Define
case $MODE in
    ram|RAM)
        DEFINE_MACRO="+define+RAM_STANDALONE"
        LOG_FILE="sim_ram_${TEST}.log"
        echo "==============================================================================="
        echo " [MODE] Compiling & Running in: STANDALONE AXI4 RAM MODE"
        echo "==============================================================================="
        ;;
    dma|DMA)
        DEFINE_MACRO="+define+DMA_STANDALONE"
        LOG_FILE="sim_dma_${TEST}.log"
        echo "==============================================================================="
        echo " [MODE] Compiling & Running in: STANDALONE AXI4 DMA ENGINE MODE"
        echo "==============================================================================="
        ;;
    sys|SYS|subsystem)
        DEFINE_MACRO="+define+SUBSYSTEM"
        LOG_FILE="sim_sys_${TEST}.log"
        echo "==============================================================================="
        echo " [MODE] Compiling & Running in: FULL SUBSYSTEM LOOPBACK MODE"
        echo "==============================================================================="
        ;;
    *)
        echo "[ERROR] Unknown mode '$MODE'. Use -mode ram, -mode dma, or -mode sys."
        exit 1
        ;;
esac

# Execute Cadence Xcelium (xrun)
CMD="xrun -64bit -sv -uvm \
     -timescale 1ns/1ns \
     -access +rwc \
     -svseed $SEED \
     $DEFINE_MACRO \
     +UVM_TESTNAME=$TEST \
     +UVM_VERBOSITY=$VERBOSITY \
     -f filelist.f \
     -l $LOG_FILE \
     $GUI \
     $EXTRA_ARGS"

echo "[COMMAND] $CMD"
echo ""

eval $CMD
