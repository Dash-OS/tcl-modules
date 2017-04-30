# flags: -all -get
proc cswitch {args} {
  set flags   [list]
  set results [dict create]
  set i -1
  foreach arg $args {
    if { ! [string equal [string index $arg 0] -] } { break }
    if { $arg eq "--" } { continue }
    lappend flags $arg
  }
  set next 0
  set add_result [list if { "-get" in $flags } { dict set results $i $result }]
  dict for { check body } $arg {
    set passes $next
    incr i
    if { ! $passes } { 
      if { [uplevel 1 expr [list $check]] } { 
        if { $body eq "-" } { set next 1 ; continue } 
        set passes 1
      }
    }
    if { $passes } {
      set next 0
      try { 
        set result [ uplevel 1 $body ]
      } on break {result} {
        try $add_result
        break
      } on return {result options} {
        switch -- [dict get $options -code] {
          3 {
            try $add_result
            break
          }
          4 { continue }
        }
      } on continue {result} {
        try $add_result
        continue
      } on error {result} {
        try $add_result
        throw error $results
      }
      try $add_result
      if { "-all" ni $flags } { break }
    }
  }
  return $results
}