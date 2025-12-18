# -----------------------------
# User configuration
# -----------------------------
set PROJECT_NAME MAC
set PART xc7a35tfgg484-2
set TOP top                     ;# top-level module name

set SRC_DIR ./src
set CONSTR_DIR ./constr
set IP_DIR ./ip

# -----------------------------
# Create project
# -----------------------------
create_project $PROJECT_NAME . -part $PART -force

# -----------------------------
# IP handling
# -----------------------------
set ip_files [glob -nocomplain $IP_DIR/**/*.xci]

if {[llength $ip_files] > 0} {
    puts "Found IP:"
    foreach ip $ip_files { puts "  $ip" }

    import_ip $ip_files

    upgrade_ip [get_ips *]
    generate_target all [get_ips *]
    synth_ip [get_ips *]
}

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