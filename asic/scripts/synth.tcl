##############################################################################
# Cadence Genus Synthesis Script
# Target Design: axi_dma (Top-Level Controller)
# Sub-modules:   axi_dma_rd, axi_dma_wr
# Target Tech:   tutorial.lib (Cadence Generic CMOS Standard Cell Library)
# Target Clock:  166.0 MHz (Period = 6.024 ns / 6024 ps)
##############################################################################

set_db information_level 6

# Create output and report directories relative to execution root
file mkdir ../reports
file mkdir ../output

# Technology Library and RTL Search Paths
# Note: Adjust init_lib_search_path to match your Cadence installation environment
set_db init_lib_search_path { 
    /home/installs/GENUS201/share/synth/tutorials/tech 
    /cadence/genus/tutorials/tech
    .
}
set_db init_hdl_search_path { 
    ../../axi4_rtl/axi_master_rtl 
    ../rtl 
    ../rtl/axi_master_rtl 
    .
}

# Load standard cell library
set_db library { tutorial.lib }

# Read synthesizable Verilog RTL source files
read_hdl -v2001 {
    axi_dma_rd.v
    axi_dma_wr.v
    axi_dma.v
}

# Elaborate top-level module
elaborate axi_dma

# Structural Lint & Unresolved References Check
check_design -unresolved > ../reports/check_design.rpt

##############################################################################
# Timing Constraints (166.0 MHz Maximum Operating Target)
##############################################################################
set CLK_PERIOD 6.024
set CLK_UNCERT 0.060
set IO_DELAY   1.200

create_clock -name "clk" -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty $CLK_UNCERT [get_clocks clk]

set_input_delay  -clock clk $IO_DELAY [all_inputs -no_clocks]
set_output_delay -clock clk $IO_DELAY [all_outputs]

# Treat asynchronous active-low reset as a false path
set_false_path -from [get_ports rst]

##############################################################################
# Synthesis Optimization Pipeline
##############################################################################
syn_generic
syn_map
syn_opt

##############################################################################
# Quality of Results (QoR) Report Generation
##############################################################################
report_timing > ../reports/timing.rpt
report_area   > ../reports/area.rpt
report_power  > ../reports/power.rpt
report_qor    > ../reports/qor.rpt
report_gates  > ../reports/gates.rpt

##############################################################################
# Export Gate-Level Netlist and Constraints
##############################################################################
write_hdl > ../output/axi_dma_netlist.v
write_sdc > ../output/axi_dma.sdc

puts "\n=================================================================="
puts "  166 MHz Maximum Frequency Synthesis Run Finished!"
puts "  Reports saved in: ../reports/"
puts "  Deliverables in:  ../output/"
puts "==================================================================\n"
