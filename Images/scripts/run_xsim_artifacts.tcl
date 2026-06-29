proc run_artifact {top vcd_path} {
  log_wave -recursive *
  open_vcd $vcd_path
  log_vcd [get_objects -r /*]
  run all
  close_vcd
  quit
}
