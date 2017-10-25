# this is being used to do a quick benchmark of how tclquadcode will affect
# the speed of such procedures as optcmds

namespace eval ::optcmds {
  namespace export oproc omethod oapply
}

# parsed received $args when the given command is invoked
proc ::optcmds::eatargs {argnames odef} {
  upvar 1 args args
  upvar 1 opts opts
  set opts [dict create]
  set i -1;
  if {![llength $args]} {
    return
  }
  while {1} {
    set opt [lindex $args [incr i]]
    if {[dict exists $odef $opt] && $opt ne "--"} {
      if {[dict get $odef $opt] eq {}} {
        dict set opts $opt 1
      } else {
        set val [lindex $args [incr i]]
        if {$val eq {} || $val eq "--" || ([string index $val 0] eq "-" && [dict exists $odef $val])} {
          tailcall return \
            -code error \
            -errorCode [list PROC_OPTS INVALID_OPT VALUE_REQUIRED $opt] \
            " option \"$opt\" expects a value \"[dict get $odef $opt]\" but none was provided"
        }
        dict set opts $opt $val
      }
    } elseif {$opt ne "--"} {
      incr i -1
      break
    } else {
      break
    }
  }
  set args [lreplace $args[set args {}] 0 $i]
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
    foreach name [lrange $argnames 0 end-1] {
      if {![llength $args]} {
        tailcall return \
          -code error \
          -errorCode [list TCL WRONGARGS] \
          "wrong #args: should be \"$argnames\""
      }
      set args  [lassign $args val]
      uplevel 1 [list set $name $val]
    }
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
  set odef  [dict create -- {}]

  set oargs [lassign $oargs opt]
  while {$opt ne {}} {
    set key   $opt
    set oargs [lassign $oargs opt]
    if {[string index $opt 0] ne "-"} {
      dict set odef $key $opt
      set oargs [lassign $oargs opt]
    } else {
      dict set odef $key {}
    }
  }

  set process [format {::optcmds::eatargs [list %s] [dict create %s]} $argnames $odef]

  switch -- $kind {
    apply {
      # set cmd [format \
      #   {::apply {args {%s;%s} {%s}} %s} \
      #   $process $argnames $body $name $args
      # ]
      set cmd [list ::apply [list args [join [list $process $body] \;] $name] {*}$args]
    }
    default {
      set cmd [format {%s %s args {%s;%s}} $kind $name $process $body]
    }
  }

  if {[info exists opts] && [dict exists $opts -define]} {
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
proc ::optcmds::define [list -define -- {*}[info args ::optcmds::define]] [info body ::optcmds::define]

# and oproc becomes an oproc as well
::optcmds::define \
proc ::optcmds::oproc {-define -- name pargs body} {
  tailcall ::optcmds::define {*}[dict keys $opts] proc $name $pargs $body
}

# as does omethod
::optcmds::define \
proc ::optcmds::omethod {-define -- name pargs body} {
  tailcall ::optcmds::define {*}[dict keys $opts] -- method $name $pargs $body
}

# and oapply
::optcmds::define \
proc ::optcmds::oapply {-define -- spec args} {
  tailcall ::optcmds::define {*}[dict keys $opts] -- apply [lindex $spec 2] [lindex $spec 0] [lindex $spec 1] {*}$args
}

# namespace import ::optcmds::*
#
# oproc myproc {-all -inline -not -upvar varName -- one two args} {
#   if {[dict exists $opts -all]} {}
# }
#
# proc bench {} {
#   puts [time {myproc -upvar val foo bar baz qux} 10000]
# }

# oproc -define myproc {-all -inline -not -upvar varName -- one two args} {
#   if {[dict exists $opts -all]} {}
# }
