# This script can be used to add simplify adding BRAM signals to the waveform viewer in Vivado simulations.
# The problem is that in the Control Unit module, the BRAM signals are in arrays, grouped by signal type and not BRAM instance.
# (all addr_a signals are together, all din_a signals are together, etc.)
# This script creates wave groups for each BRAM instance and adds the relevant signals into them.
# 
# This is designed to be used in the instruction_dispatch_tb simulation testbench, but can be adapted for others. 
# Note that the signal sizes are hardcoded (e.g. [12:0], [127:0]), so if the BRAM configurations change, the script needs to be updated accordingly.
#
# Usage: while the simulation is open, copy this script into the Tcl console and run it. Move the groups as desired. 

for {set i 0} {$i < 7} {incr i} {
  set group_name "bram$i"
  set tb_name "instruction_dispatch_tb"
  set path "/$tb_name/instruction_dispatch/control_unit"
  add_wave_group $group_name

  add_wave -into $group_name -name "addr_a[12:0]" -radix unsigned $path/bram_addr_a($i)
  add_wave -into $group_name -name "din_a[127:0]"                $path/bram_din_a($i)
  add_wave -into $group_name -name "dout_a[127:0]"               $path/bram_dout_a($i)
  add_wave -into $group_name -name "we_a"                        $path/bram_we_a($i)

  add_wave -into $group_name -name "addr_b[12:0]" -radix unsigned $path/bram_addr_b($i)
  add_wave -into $group_name -name "din_b[127:0]"                $path/bram_din_b($i)
  add_wave -into $group_name -name "dout_b[127:0]"               $path/bram_dout_b($i)
  add_wave -into $group_name -name "we_b"                        $path/bram_we_b($i)
}
