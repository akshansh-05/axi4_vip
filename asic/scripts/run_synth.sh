#!/usr/bin/env bash
##############################################################################
# Cadence Genus Synthesis Execution Script (166 MHz Maximum Frequency Target)
# Usage:
#   ./run_synth.sh
##############################################################################

echo "=================================================================="
echo " Starting Cadence Genus Synthesis for AXI4 DMA Subsystem"
echo " Target Frequency: 166.0 MHz (Period: 6.024 ns)"
echo "=================================================================="

# Ensure script is executed from the scripts directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" || exit 1

genus -files synth.tcl

echo "=================================================================="
echo " Synthesis execution completed. Reports available in asic/reports/"
echo "=================================================================="
