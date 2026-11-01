# Create the Zynq UltraScale+ project with the block design that integrates the Falcon IP core.
#
# Usage: vivado -mode batch -source vivado/create_bd_project.tcl -tclargs [project_dir] [ip_repo_dir] [N]
#        (defaults: build/bd_<N>, build/ip_repo, 512). Package the IP first (vivado/package_ip.tcl).
#
# The block design itself is in vivado/bd/falcon_bd.tcl (generated with write_bd_tcl -no_ip_version).
# To change it: edit it in the GUI, then File > Export > Export Block Design (or run
#   write_bd_tcl -force -no_ip_version -include_layout <repo>/vivado/bd/falcon_bd.tcl
# in the Tcl console) and commit the updated script.

source [file join [file dirname [info script]] common.tcl]

set N        [expr {[llength $argv] > 2 ? [lindex $argv 2] : 512}]
set proj_dir [arg 0 [file join $repo_root build bd_$N]]
set ip_repo  [arg 1 [file join $repo_root build ip_repo]]

if {$N ni {512 1024}} { error "N must be 512 or 1024, got $N" }
if {![file exists [file join $ip_repo falcon component.xml]]} {
  error "Falcon IP not found in $ip_repo, run vivado/package_ip.tcl first (make ip)"
}

create_project -force falcon_bd $proj_dir -part $part
# The design was made for the TUL PYNQ-ZU board; use its board files when they are installed
set board [lindex [get_board_parts -quiet -latest_file_version *pynqzu*] 0]
if {$board ne ""} { set_property board_part $board [current_project] }

set_property ip_repo_paths $ip_repo [current_project]
update_ip_catalog

source [file join $repo_root vivado bd falcon_bd.tcl]
set_property CONFIG.N $N [get_bd_cells falcon_0]
validate_bd_design
save_bd_design

set bd_file [get_files falcon.bd]
make_wrapper -files $bd_file -top
add_files -norecurse [file join $proj_dir falcon_bd.gen sources_1 bd falcon hdl falcon_wrapper.v]
set_property top falcon_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "Created block design project [file join $proj_dir falcon_bd.xpr] (N=$N)"
