##############################################################################
# Cadence Genus Synthesis Script - 100 MHz Target (Baseline Run)
# Target Design: axi_dma (Top-Level Controller)
# Sub-modules:   axi_dma_rd, axi_dma_wr
# Target Tech:   tutorial.lib (Cadence Generic CMOS Standard Cell Library)
# Target Clock:  100.0 MHz (Period = 10.0 ns / 10000 ps)
##############################################################################

set_db information_level 6

# Create output directories relative to execution root
file mkdir ../reports/100mhz
file mkdir ../output/100mhz

# Technology Library and RTL Search Paths
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
check_design -unresolved > ../reports/100mhz/check_design.rpt

##############################################################################
# Timing Constraints (100.0 MHz Baseline Target)
##############################################################################
set CLK_PERIOD 10.000
set CLK_UNCERT 0.100
set IO_DELAY   2.000

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
report_timing > ../reports/100mhz/timing.rpt
report_area   > ../reports/100mhz/area.rpt
report_power  > ../reports/100mhz/power.rpt
report_qor    > ../reports/100mhz/qor.rpt
report_gates  > ../reports/100mhz/gates.rpt

##############################################################################
# Export Gate-Level Netlist and Constraints
##############################################################################
write_hdl > ../output/100mhz/axi_dma_netlist.v
write_sdc > ../output/100mhz/axi_dma.sdc

puts "\n=================================================================="
puts "  100 MHz Synthesis Run Finished Successfully!"
puts "  Reports saved in: ../reports/100mhz/"
puts "  Deliverables in:  ../output/100mhz/"
puts "==================================================================\n"
