# this is being used to do a quick benchmark of how tclquadcode will affect
# the speed of such procedures as optcmds

namespace eval ::optcmds {
  namespace export oproc omethod oapply
}

# parsed received $args when the given command is invoked
proc ::optcmds::eatargs {argnames odef} {
  upvar 1 args args
  set name [dict get $odef name]
  # upvar 1 $name opts

  set opts [dict get $odef defaults]
  set raw  $opts
  set alength [llength $args]

  if {$alength} {
    set i -1;
    while {1} {
      set opt [lindex $args [incr i]]
      if {[dict exists $odef schema $opt] && $opt ne "--"} {
        if {[dict get $odef schema $opt] eq {}} {
          dict set opts $opt 1
          lappend raw $opt
        } else {
          set val [lindex $args [incr i]]
          if {$alength < $i || $val eq "--" || ([string index $val 0] eq "-" && [dict exists $odef schema $val])} {
            tailcall return -code error -errorCode [list PROC_OPTS INVALID_OPT VALUE_REQUIRED $opt] " option \"$opt\" expects a value \"[dict get $odef schema $opt]\" but none was provided"
          }
          dict set opts $opt $val
          if {$opt in $raw} {
            set idx [lsearch $raw $opt]
            set raw [lreplace $raw[set raw {}] ${idx}+1 ${idx}+1 $val]
          } else {
            lappend raw $opt $val
          }

        }
      } elseif {$opt ne "--"} {
        incr i -1
        break
      } else {
        break
      }
    }
    set args [lreplace $args[set args {}] 0 $i]
  }

  if {[lindex $argnames end] ne "args"} {
    if {[llength $argnames] != [llength $args]} {
      tailcall return \
        -code error \
        -errorCode [list TCL WRONGARGS] \
        "wrong #args: should be \"$argnames\""
    }
    uplevel 1 [list lassign $args {*}$argnames]
    unset args
  } else {
    foreach v [lrange $argnames 0 end-1] {
      if {![llength $args]} {
        tailcall return -code error -errorCode [list TCL WRONGARGS] "wrong #args: should be \"$argnames\""
      }
      set args  [lassign $args val]
      uplevel 1 [list set $v $val]
    }
  }
  if {$name eq {}} {
    uplevel 1 {
      dict with {} {}
      unset {}
    }
  } else {
    dict set opts {} $raw
    uplevel 1 [list array set $name $opts]
  }
}

proc ::optcmds::define {kind name pargs body args} {
  set oindex [lsearch -exact $pargs --]

  if {$oindex == -1} {
    switch -- $kind {
      apply   { tailcall ::apply [list $pargs $body $name] {*}$args }
      default { tailcall $kind $name $pargs $body }
    }
  }

  set argnames [lrange $pargs ${oindex}+1 end]

  if {"opts" in $argnames} {
    return \
      -code error \
      -errorCode [list OPT_PROC ILLEGAL_ARG opts] \
      " option procs may not use the arg name \"opts\""
  }

  set oargs [lrange $pargs 0 ${oindex}-1]
  set olength [llength $oargs]
  set odef [dict create schema [dict create -- {}] defaults [dict create] params [dict create]]

  if {[info exists opts(-opts)]} {
    dict set odef name $opts(-opts)
  } elseif {[info exists opts(-noopts)]} {
    dict set odef name {}
  } else {
    dict set odef name opts
  }

  set i -1
  while {1} {
    incr i
    if {$i >= $olength} { break }
    set key   [lindex $oargs $i]
    set opt   [lindex $oargs [incr i]]
    if {[string index $opt 0] ne "-"} {
      dict set odef schema $key [lindex $opt 0]
      switch -- [llength $opt] {
        0 - 1 {}
        2 { dict set odef defaults $key [lindex $opt 1] }
        default {
          dict set odef defaults $key [lindex $opt 1]
          dict set odef params   $key [lrange $opt 2 end]
        }
      }
    } else {
      dict set odef schema $key {}
      incr i -1
    }
  }

  set process [format {::optcmds::eatargs [list %s] [dict create %s]} $argnames $odef]

  switch -- $kind {
    apply   { set cmd [list ::apply [list args [join [list $process $body] \;] $name] {*}$args] }
    default { set cmd [format {%s %s args {%s;%s}} $kind $name $process $body] }
  }

  if {[info exists opts(-define)]} {
    # when this becomes optcmd itself, -define returns $cmd instead of invokes
    return $cmd
  } else {
    uplevel 1 $cmd
  }
}

# our exported commands simply call ::optcmds::define via tailcall which
# in-turn creates the given command at the callers level/namespace/frame
#
# they are themselves optcommands with -define which is passed to define
# indicating to return the cmd rather than execute it.
#
# this allows us to have the definition returns so we can either save it
# in the case of apply or use it to pass to ::oo::define {*}[omethod ...]

# now lets make define itself an oproc!
::optcmds::define \
proc ::optcmds::define [list -define -noopts -opts {optsName opts} -- {*}[info args ::optcmds::define]] [info body ::optcmds::define]

# and oproc becomes an oproc as well
::optcmds::define \
proc ::optcmds::oproc {-define -noopts -opts {optsName opts} -- name pargs body} {
  tailcall ::optcmds::define {*}$opts() -- proc $name $pargs $body
}

# as does omethod
::optcmds::define \
proc ::optcmds::omethod {-define -noopts -opts {optsName opts} -- name pargs body} {
  tailcall ::optcmds::define {*}$opts() -- method $name $pargs $body
}

# and oapply
::optcmds::define \
proc ::optcmds::oapply {-define -noopts -opts {optsName opts} -- spec args} {
  tailcall ::optcmds::define {*}$opts() -- apply [lindex $spec 2] [lindex $spec 0] [lindex $spec 1] {*}$args
}

#
# oproc -define myproc {-all -inline -not -upvar varName -- one two args} {
#   if {[dict exists $opts -all]} {}
# }
