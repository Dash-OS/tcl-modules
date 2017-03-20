namespace eval ::time {
  namespace ensemble create
  namespace export {[a-z]*}
}

# after [time in 10 seconds] { puts hi }
proc ::time::in args {
  if {[llength $args] == 1} {
    if { [string is entier -strict $args] } { return $args }
    set args [lindex $args 0]
  }
  return [expr { [clock add 0 {*}$args] * 1000 }]
}
