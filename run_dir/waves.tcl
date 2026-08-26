# File: waves.tcl
# Cadence Xcelium TCL script to dump complete waveforms into waves.shm database

database -open waves -shm -default
probe -create -shm -all -depth all tb_top
run
exit
