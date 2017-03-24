
namespace eval ::run {
  variable default [dict create scoped 0 level -1]
  proc about args {}
}

proc ::run::runner { adict body args } {
  if { $args ne {} } {
    set keys [concat [dict keys $adict] args]
  } else { set keys [dict keys $adict] }
  tailcall ::apply [list \
    $keys $body \
    [uplevel 1 { namespace current }] \
  ] {*}[dict values $adict] {*}$args
}

# run ?-scoped? ?-vars? ?-level? -- script


proc ::run { args } {
  set opts [set ::run::default]
  set body [lindex $args end]
  set args [lrange $args 0 end-1]
  if { $args ne {} && ! [string equal [string index $args 0] -] } {
    set args [lassign $args adict]
  } elseif { $args eq {} } { set adict {} }
  while 1 {
    if { $args eq {} } { break }
    set args [lassign $args arg]
    if { [string equal $arg --] } { break }
    if { [string equal [string index $arg 0] -] } {
      if { [info exists o] } { dict set opts $o 1 }
      set o [string range $arg 1 end]
    } else { 
      if { [info exists o] } { 
        dict set opts $o $arg 
        unset o
      } else { 
        lappend args $arg
        break 
      }
    }
  }
  if { [info exists o] } { dict set opts $o 1 }
  if { $args ne {} } { set adict $args }
  if { [info exists adict] && [string is entier -strict $adict] } {
    dict set opts level $adict
    set adict {}
  }
  if { [dict get $opts scoped] } {
    tailcall ::run::scoped $opts $body 
  } elseif { [dict get $opts level] != -1 } {
    set level [dict get $opts level]
    if { ! [string equal [string index $level 0] \#] } { 
      set level [expr { $level + 1 }]
    }
    tailcall ::apply [list \
      {} \
      [format {uplevel %s [list try {%s}]} $level $body]
    ]
  } else {
    if { ! [info exists adict] } { set adict {} }
    tailcall ::run::runner $adict $body
  }
}

proc ::run::scoped { opts {body {}} } {
  if { $body eq {} } { set body $opts ; set opts [set ::run::default] }
  set level [dict get $opts level]
  if { ! [string equal [string index $level 0] \#] } {
    if { $level == -1 } { 
      set level 1
    } else { set level [expr { $level + 1 }] }
  }
  if { [dict exists $opts vars] } {
    set vars [dict get $opts vars]
  } else {
    set vars [uplevel $level {info vars}] 
  }
  if { [dict exists $opts upvar] && [dict get $opts upvar] } {
    set cmd [format { catch { upvar %s ${___v} ${___v} } } $level]
  } else {
    set cmd [format { catch { set [set ___v] [uplevel %s set ${___v}] } } $level ]
  }
  tailcall ::run::runner [dict create __v $vars] [format {
    foreach ___v ${__v}[unset __v] { %s }; catch { unset ___v } ; %s
  } $cmd $body]
}

