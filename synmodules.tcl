#!/bin/sh
##
## tcl procedures to output all generated object files of all modules that are
## marked "synthesize" in a bluespec package

## \
exec bluetcl "$0" "$@"

#

# scan options looking for command line options that we should consume
# (instead of passing to BlueTcl).
set pkg [lindex $argv [expr $argc -1]]

utils::scanOptions [list -no-show-timestamps] [list -o] 0 OPT $argv
set outfile stdout
if { [info exists OPT(-o)] } {
  if { [catch "open $OPT(-o) w" err] } {
    puts stderr $err
    exit 1
  } else {
    set outfile $err
  }
}

set flags [lrange $argv 0 [expr $argc -2]]

if { $flags != "" } {
  if { [catch "Bluetcl::flags set $flags" err] } {
    puts stderr $err
    exit 1
  }
}

Bluetcl::bpackage load $pkg
if { [catch "Bluetcl::defs module $pkg" modules] } {
  exit 1
}

foreach module $modules {
  regsub -- {(.*)::(.*)} $module {\2.o} object
  puts $outfile $object
}

exit 0
