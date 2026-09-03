# File: waves.tcl
# Cadence Xcelium TCL script to dump complete signals and internal memories into waves.shm

database -open waves -shm -default
probe -create -shm -all -depth all -memories tb_top
run
exit
