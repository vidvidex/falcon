# Shared settings for the Vivado Tcl flow. Sourced by the other scripts in this directory.

set repo_root [file normalize [file join [file dirname [info script]] ..]]
set part      xczu5eg-sfvc784-1-e

# RTL sources, read from rtl/files.f (the same list Verilator and the Makefile use)
proc rtl_files {} {
  global repo_root
  set files {}
  set fh [open [file join $repo_root rtl files.f] r]
  foreach line [split [read $fh] "\n"] {
    set line [string trim $line]
    if {$line eq "" || [string match "+*" $line] || [string match "//*" $line]} { continue }
    lappend files [file join $repo_root $line]
  }
  close $fh
  return $files
}

proc rtl_include_dir {} {
  global repo_root
  return [file join $repo_root rtl common]
}

# Command-line argument with a default
proc arg {idx default} {
  global argv
  if {[llength $argv] > $idx} { return [file normalize [lindex $argv $idx]] }
  return $default
}
