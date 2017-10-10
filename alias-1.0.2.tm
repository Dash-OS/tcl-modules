# Reference: http://wiki.tcl.tk/38650
proc alias {alias target} {
  set fulltarget [uplevel [list namespace which $target]]
  if {$fulltarget eq {}} {
    return -code error [list {no such command} $target]
  }
  set save [namespace eval [namespace qualifiers $fulltarget] {namespace export}]
  namespace eval [namespace qualifiers $fulltarget] {namespace export *}
  while {[namespace exists [set tmpns [namespace current]::[info cmdcount]]]} {}
  set code [catch {set newcmd [namespace eval $tmpns [
      string map [list @{fulltarget} [list $fulltarget]] {
      namespace import @{fulltarget}
  }]]} cres copts]
  namespace eval [namespace qualifiers $fulltarget] [list namespace export {*}$save]
  if {$code} {
    return -options $copts $cres
  }
  uplevel [list rename ${tmpns}::[namespace tail $target] $alias]
  namespace delete $tmpns
  tailcall namespace which $alias
}
