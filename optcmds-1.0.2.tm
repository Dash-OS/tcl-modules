namespace eval ::optcmds {
  namespace export oproc omethod oapply
}

variable ::optcmds::error_expects_val {
  return \
    -code error \
    -errorCode [list PROC_OPTS INVALID_OPT VALUE_REQUIRED $opt] \
    " option \"$opt\" expects a value \"[dict get $odef $opt]\" but none was provided"
}

# parsed received $args when the given command is invoked
variable ::optcmds::eval_parse_opts {
  set opts [dict create]
  while {[dict exists $odef [lindex $args 0]]} {
    set args [lassign $args opt]
    if {$opt eq "--"} { break }
    if {[dict get $odef $opt] eq {}} {
      dict set opts $opt 1
    } elseif {![llength $args]} {
      try $::optcmds::error_expects_val
    } else {
      set args [lassign $args val]
      # TODO: should this throw an error?  its possible this arg wants the
      #       name of another arg as its parameter - however probably best
      #       to use the name without the - switch in that case.  open to
      #       ideas here.
      if {[string index $val 0] eq "-" && [dict exists $odef $val]} {
        try $::optcmds::error_expects_val
      }
      dict set opts $opt $val
    }
  }
}

proc ::optcmds::define {kind name pargs body args} {
  set oindex [lsearch -exact $pargs --]

  if {$oindex == -1} {
    # not valid optcmd syntax, create as normal command
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
      if {[string index $opt 0] ne "-"} {
        dict set odef $key $opt
        set oargs [lassign $oargs opt]
      }
    } else {
      dict set odef $key {}
    }
  }

  set process [list [list set odef $odef] [list set argnames $argnames] {try $::optcmds::eval_parse_opts}]

  switch -- $kind {
    apply {
      set cmd [format \
        {::apply {args {%s;::tailcall ::apply [::list {opts %s} {%s} [::namespace current]] $opts {*}$args} {%s}} %s} \
        [join $process \;] $argnames $body $name $args
      ]
    }
    default {
      set cmd [format \
        {%s %s args {%s;::tailcall ::apply [::list {opts %s} {%s} [::namespace current]] $opts {*}$args}} \
        $kind $name [join $process \;] $argnames $body
      ]
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
  tailcall ::optcmds::define {*}[dict keys $opts] -- proc $name $pargs $body
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
