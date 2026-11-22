#!/usr/bin/env bash
##############################################################################
# Cadence Genus Synthesis Execution Wrapper Script
# Usage:
#   ./run_synth.sh 166    # Runs 166 MHz synthesis (default)
#   ./run_synth.sh 100    # Runs 100 MHz baseline synthesis
##############################################################################

TARGET_FREQ=${1:-166}

echo "=================================================================="
echo " Starting Cadence Genus Synthesis for AXI4 DMA Subsystem"
echo " Target Frequency: ${TARGET_FREQ} MHz"
echo "=================================================================="

# Ensure script is executed from the scripts directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" || exit 1

if [ "$TARGET_FREQ" -eq "166" ]; then
    echo "Executing: genus -files synth_166mhz.tcl"
    genus -files synth_166mhz.tcl
elif [ "$TARGET_FREQ" -eq "100" ]; then
    echo "Executing: genus -files synth_100mhz.tcl"
    genus -files synth_100mhz.tcl
else
    echo "Error: Unsupported frequency target '$TARGET_FREQ'. Specify 100 or 166."
    exit 1
fi

echo "Synthesis execution completed."
