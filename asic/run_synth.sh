#!/usr/bin/env bash
##############################################################################
# Cadence Genus Synthesis Execution Script (166.67 MHz Nominal Target)
# Usage:
#   ./run_synth.sh
##############################################################################

echo "=================================================================="
echo " Starting Cadence Genus Synthesis for AXI4 DMA Subsystem"
echo " Target Frequency: 166.67 MHz (Clock Period: 6.000 ns / 6000 ps)"
echo "=================================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" || exit 1

genus -files synth.tcl

echo "=================================================================="
echo " Synthesis execution completed. Reports available in reports/"
echo "=================================================================="
