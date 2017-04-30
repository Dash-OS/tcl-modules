proc cswitch {args} {

  set flags [list] ; set results [dict create] ; set next 0 ; set i -1
  set add_result [list if { "-get" in $flags } { dict set results $i $result }]
  
  foreach arg $args {
    if { ! [string equal [string index $arg 0] -] } { break }
    if { $arg eq "--" } { continue }
    lappend flags $arg
  }
  if { [string first \# $arg] ne -1 } {
    set arg [ regsub -all {#.*?\n} $arg \n]
  }
  
  dict for { check body } $arg {
    incr i ; set passes $next
    if { ! $passes } { 
      if { [uplevel 1 expr $check] } { 
        if { [string index $body 0] eq "-" } { set next 1 ; continue } 
        set passes 1
      }
    } elseif { [string index $body 0] eq "-" } { continue }
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