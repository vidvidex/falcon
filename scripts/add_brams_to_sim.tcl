for {set i 0} {$i < 7} {incr i} {
  set group_name "bram$i"
  set tb_name "control_unit_sign_tb"
  add_wave_group $group_name

  add_wave -into $group_name -name "addr_a[12:0]" -radix unsigned /$tb_name/control_unit/bram_addr_a($i)
  add_wave -into $group_name -name "din_a[127:0]"                /$tb_name/control_unit/bram_din_a($i)
  add_wave -into $group_name -name "dout_a[127:0]"               /$tb_name/control_unit/bram_dout_a($i)
  add_wave -into $group_name -name "we_a"                        /$tb_name/control_unit/bram_we_a($i)

  add_wave -into $group_name -name "addr_b[12:0]" -radix unsigned /$tb_name/control_unit/bram_addr_b($i)
  add_wave -into $group_name -name "din_b[127:0]"                /$tb_name/control_unit/bram_din_b($i)
  add_wave -into $group_name -name "dout_b[127:0]"               /$tb_name/control_unit/bram_dout_b($i)
  add_wave -into $group_name -name "we_b"                        /$tb_name/control_unit/bram_we_b($i)
}
