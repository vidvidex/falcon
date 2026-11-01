# Build the hardware platform: block design project -> bitstream -> .xsa (for Vitis).
#
# Usage: vivado -mode batch -source vivado/build.tcl -tclargs [project_dir] [ip_repo_dir] [N] [xsa_file] [jobs]
#        (defaults: build/bd_<N>, build/ip_repo, 512, build/falcon_<N>.xsa, 8)

source [file join [file dirname [info script]] common.tcl]

set N    [expr {[llength $argv] > 2 ? [lindex $argv 2] : 512}]
set xsa  [arg 3 [file join $repo_root build falcon_$N.xsa]]
set jobs [expr {[llength $argv] > 4 ? [lindex $argv 4] : 8}]

# Creates and opens the project (uses the same project_dir / ip_repo_dir / N arguments)
source [file join $repo_root vivado create_bd_project.tcl]

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
  error "Implementation failed, see [get_property DIRECTORY [get_runs impl_1]]"
}

open_run impl_1
report_utilization    -file [file join [file dirname $xsa] falcon_${N}_utilization.rpt]
report_timing_summary -file [file join [file dirname $xsa] falcon_${N}_timing.rpt]
if {[get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]] < 0} {
  puts "CRITICAL WARNING: design does not meet timing, see falcon_${N}_timing.rpt"
}

write_hw_platform -fixed -include_bit -force $xsa
puts "Wrote $xsa"
