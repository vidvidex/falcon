# Package the Falcon accelerator (top: axi_wrapper) as IP core user.org:user:falcon:1.0
#
# Usage: vivado -mode batch -source vivado/package_ip.tcl -tclargs [ip_repo_dir]
#        (default ip_repo_dir: build/ip_repo; the core ends up in <ip_repo_dir>/falcon)

source [file join [file dirname [info script]] common.tcl]

set ip_repo [arg 0 [file join $repo_root build ip_repo]]
set ip_dir  [file join $ip_repo falcon]
set tmp_dir [file join $repo_root build package_ip]

file delete -force $ip_dir $tmp_dir
create_project -force package_ip $tmp_dir -part $part

add_files -norecurse [rtl_files]
add_files -norecurse [file join [rtl_include_dir] common_definitions.vh]
set_property file_type {Verilog Header} [get_files common_definitions.vh]
set_property top axi_wrapper [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir $ip_dir -vendor user.org -library user -taxonomy /UserIP -import_files -set_current true

set core [ipx::current_core]
set_property name         falcon                          $core
set_property version      1.0                             $core
set_property display_name "Falcon signature accelerator"  $core
set_property description  "Falcon-512/1024 signing and verification, controlled over AXI-Lite" $core
set_property supported_families {zynquplus Production} $core

# N (512 or 1024) is the only user parameter
set_property value_validation_type list [ipx::get_user_parameters N -of_objects $core]
set_property value_validation_list {512 1024} [ipx::get_user_parameters N -of_objects $core]

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core

close_project
file delete -force $tmp_dir
puts "Packaged IP core to $ip_dir"
