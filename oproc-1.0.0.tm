namespace eval oproc {

  variable error_expects_val {
    return \
      -code error \
      -errorCode [list PROC_OPTS INVALID_OPT VALUE_REQUIRED $opt] \
      " option $opt expects a value \"[dict get $odef $opt]\" but none was provided"
  }

  variable error_illegal_opt {
    return \
      -code error \
      -errorCode [list PROC_OPTS INVALID_OPT NOT_ALLOWED $opt] \
      " option $opt is not allowed.  available options are [dict keys $odef]"
  }

  variable simple_eval {
    set opts [dict create]
    while {[llength $oargs]} {
      set oargs [lassign $oargs opt]
      if {![dict exists $odef $opt]} {
        try $::oproc::error_illegal_opt
      } elseif {[dict get $odef $opt] eq {}} {
        dict set opts [string trimleft $opt -] 1
      } elseif {![llength $oargs]} {
        try $::oproc::error_expects_val
      } else {
        set oargs [lassign $oargs val]
        # should this throw an error?  its possible this arg wants the
        # name of another arg as its parameter - however probably best
        # to use the name without the - switch in that case.  open to
        # ideas here.
        if {[string index $val 0] eq "-" && [dict exists $odef $val]} {
          try $::oproc::error_expects_val
        }
        dict set opts [string trimleft $opt -] $val
      }
    }
  }

  # main downside here is that we really do not have a way of
  # reliably determining if we have received an invalid opt or
  # if it is meant to be apart of the regular arguments.  thus, the
  # -- is highly recommended when using $args for better error messages
  # and more reliable handling.
  variable args_eval {
    set opts [dict create]
    while {[dict exists $odef [lindex $args 0]]} {
      set args [lassign $args opt]
      if {[dict get $odef $opt] eq {}} {
        dict set opts [string trimleft $opt -] 1
      } elseif {![llength $args]} {
        try $::oproc::error_expects_val
      } else {
        set args [lassign $args val]
        if {[string index $val 0] eq "-" && [dict exists $odef $val]} {
          try $::oproc::error_expects_val
        }
        dict set opts [string trimleft $opt -] $val
      }
    }
  }

}

proc oproc {name pargs body} {
  set oindex   [lsearch -exact $pargs --]
  set oargs    [lrange $pargs 0 ${oindex}-1]
  set argnames [lrange $pargs ${oindex}+1 end]
  set opts     [dict create -- {}]

  if {"opts" in $argnames} {
    # not sure that this should throw an error
    # but ... since it makes no sense ...
    return \
      -code error \
      -errorCode [list OPT_PROC ILLEGAL_ARG opts] \
      " option procs may not use the arg name \"opts\""
  }

  set oargs    [lassign $oargs opt]
  while {$opt ne {}} {
    set key   $opt
    set oargs [lassign $oargs opt]
    if {[string index $opt 0] ne "-"} {
      dict set opts $key $opt
      set oargs [lassign $oargs opt]
    } else {
      dict set opts $key {}
    }
  }

  set process [list [list set odef $opts] [list set argnames $argnames]]

  if {[lindex $argnames end] ne "args"} {
    # optimized version
    lappend process {
      set oargs [lrange $args 0 end-[llength $argnames]]
      set args  [lrange $args end-[expr {[llength $argnames] - 1}] end]
      try $::oproc::simple_eval
    }
  } else {
    # handle when dynamic args are at the end.  here we cant easily separate the
    # flags since we cant know how many arguments and/or flags that we
    # may have. If -- is provided we may optimize things, otherwise we
    # need to parse one-by-one until we find what "appears" to be a non-matching
    # value.
    lappend process {
      set dashdash [lsearch -exact $args --]
      if {$dashdash != -1} {
        set oargs [lrange $args 0 ${dashdash}-1]
        set args [lrange $args ${dashdash}+1 end]
        try $::oproc::simple_eval
      } else {
        try $::oproc::args_eval
      }
    }
  }

  uplevel 1 [format {
    proc %s args {
      %s
      tailcall ::apply [list {opts %s} {%s} [namespace current]] $opts {*}$args
    }
  } $name [join $process \;] $argnames $body]
}
