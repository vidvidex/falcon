# Create a Vivado project for the accelerator RTL and its SV testbenches (for GUI work).
# The project only references files in the repo, so edits made in the GUI land in rtl/ and tb/.
#
# Usage: vivado -mode batch -source vivado/create_project.tcl -tclargs [project_dir]
#        (default project_dir: build/vivado), then open <project_dir>/falcon_ip.xpr

source [file join [file dirname [info script]] common.tcl]

set proj_dir [arg 0 [file join $repo_root build vivado]]
create_project -force falcon_ip $proj_dir -part $part

# Design sources
add_files -norecurse [rtl_files]
add_files -norecurse [file join [rtl_include_dir] common_definitions.vh]
set_property file_type {Verilog Header} [get_files common_definitions.vh]
set_property include_dirs [rtl_include_dir] [get_filesets sources_1]
set_property top axi_wrapper [get_filesets sources_1]

# Simulation sources
set sim [get_filesets sim_1]
add_files -fileset sim_1 -norecurse [glob [file join $repo_root tb sv *_tb.sv]]
add_files -fileset sim_1 -norecurse [glob [file join $repo_root tb sv wcfg *.wcfg]]
set_property include_dirs [rtl_include_dir] $sim
# Memory images: testbench BRAM images, and the debug BRAM contents for instruction_dispatch_tb
set mem_dir [file join $repo_root mem]
set_property verilog_define [list \
  "FALCON_MEM_DIR=\"$mem_dir\"" \
  "FALCON_BRAM_INIT_DIR=\"$mem_dir/instruction_dispatch_tb/sign512\""] $sim
set_property top instruction_dispatch_tb $sim
set_property top_lib xil_defaultlib $sim

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project
puts "Created project [file join $proj_dir falcon_ip.xpr]"
