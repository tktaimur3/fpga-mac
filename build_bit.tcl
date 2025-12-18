# -----------------------------
# User configuration
# -----------------------------
set PROJECT_NAME MAC_PROJ
set PART xc7a35tfgg484-2
set TOP top                     ;# top-level module name

set SRC_DIR ./MAC.srcs/sources_1/new
set CONSTR_DIR ./MAC.srcs/constrs_1/new

# -----------------------------
# Create project
# -----------------------------
create_project $PROJECT_NAME . -part $PART

# -----------------------------
# Add RTL sources
# -----------------------------
add_files [glob $SRC_DIR/*.sv]

# -----------------------------
# Add constraints
# -----------------------------
add_files -fileset constrs_1 [glob $CONSTR_DIR/*.xdc]

# -----------------------------
# Set top module
# -----------------------------
set_property top $TOP [current_fileset]

# -----------------------------
# Update compile order
# -----------------------------
update_compile_order -fileset sources_1

# -----------------------------
# Synthesis
# -----------------------------
launch_runs synth_1 -jobs 8
wait_on_run synth_1
open_run synth_1
report_utilization -file utilization.txt

# -----------------------------
# Implementation + bitstream
# -----------------------------
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
open_run impl_1
report_timing_summary -file timing.txt

puts "\nBitstream generation complete!"