for {set i 0} {$i < 6} {incr i} {
  set group_name "fft_bram$i"
  set tb_name "control_unit_verify_tb"
  add_wave_group $group_name

  add_wave -into $group_name -name "addr_a[8:0]" -radix unsigned /$tb_name/control_unit/fft_bram_addr_a($i)
  add_wave -into $group_name -name "din_a[127:0]"                /$tb_name/control_unit/fft_bram_din_a($i)
  add_wave -into $group_name -name "dout_a[127:0]"               /$tb_name/control_unit/fft_bram_dout_a($i)
  add_wave -into $group_name -name "we_a"                        /$tb_name/control_unit/fft_bram_we_a($i)

  add_wave -into $group_name -name "addr_b[8:0]" -radix unsigned /$tb_name/control_unit/fft_bram_addr_b($i)
  add_wave -into $group_name -name "din_b[127:0]"                /$tb_name/control_unit/fft_bram_din_b($i)
  add_wave -into $group_name -name "dout_b[127:0]"               /$tb_name/control_unit/fft_bram_dout_b($i)
  add_wave -into $group_name -name "we_b"                        /$tb_name/control_unit/fft_bram_we_b($i)
}

for {set i 0} {$i < 2} {incr i} {
  set group_name "ntt_bram$i"
  set tb_name "control_unit_verify_tb"
  add_wave_group $group_name

  add_wave -into $group_name -name "addr_a[9:0]" -radix unsigned /$tb_name/control_unit/ntt_bram_addr_a($i)
  add_wave -into $group_name -name "din_a[14:0]" -radix dec   /$tb_name/control_unit/ntt_bram_din_a($i)
  add_wave -into $group_name -name "dout_a[14:0]" -radix dec  /$tb_name/control_unit/ntt_bram_dout_a($i)
  add_wave -into $group_name -name "we_a"                        /$tb_name/control_unit/ntt_bram_we_a($i)

  add_wave -into $group_name -name "addr_b[9:0]" -radix unsigned /$tb_name/control_unit/ntt_bram_addr_b($i)
  add_wave -into $group_name -name "din_b[14:0]" -radix dec   /$tb_name/control_unit/ntt_bram_din_b($i)
  add_wave -into $group_name -name "dout_b[14:0]" -radix dec  /$tb_name/control_unit/ntt_bram_dout_b($i)
  add_wave -into $group_name -name "we_b"                        /$tb_name/control_unit/ntt_bram_we_b($i)
}