package require decorator

namespace eval ::decorator::namedargs {}

proc switch {
  -exact
  -glob
  -regexp
  -nocase
  -matchvar varName
  -indexvar varName
  --
  var body args
} {
  # ...
}

proc ::clock::format {timeVal -- -format format -timezone timezone -local locale ... } {

}

proc lsearch {
  {-exact -glob -regexp -sorted -all -start index -ascii ...}
  list pattern
} { }

proc lsearch {
  -exact
  -glob
  -regexp and
  -sorted
  -all
  -inline
  -not
  -start index
  -ascii
  -dictionary
  -integer
  -nocase
  -real
  -decreasing
  -increasing
  -bisect
  -index indexList
  -subindices
  --
  list pattern
} {
  if {[info exists -exact]} {
    # dont need to exact this var - it will simply be 1/true since it had
    # no value
  }
  # -- is optional, it indicates that we are moving on to the args but it may
  #    also optionally be provided before the caller provides args
  #
  # -index and -start would have values associated with them - a bit annoying
  # to access via ${-start} but [set -start] is not that bad.  better than
  # making all those variables available without the preceeding - imho
  #
  # would be able to produce nice error messages to the caller as well
  # "unknown argmument -nocas did you mean -nocase?"
  # "unknown argument -blah must be one of $flags"

}

# reduce reuse

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

  uplevel 1 format {
    proc %s args {
      %s
      tailcall ::apply [list {opts %s} {%s} [namespace current]] $opts {*}$args
    }
  } $name [join $process \;] $argnames $body
}

# ok
namespace eval t {
  oproc test {-exact -start index -match -- list pattern} {
    puts "opts | $opts"
    puts "list | $list"
    puts "pattern | $pattern"
  }
}

decorator define @named { definition command args } \
  -compile {
    switch -- $command {
      method - proc {
        set argopts [dict create]
        lassign $args proc_name argnames body
        foreach argname $argnames {
          set include 1
          set opts [lassign $argname argname] ; set arg_named [list]
          if { [string equal [string index $argname 0] &] } {
            if { [llength $argname] > 1 } {
              lassign $argname argname as n
              if { $n eq {} } {
                set n 1
              }
            } else {
              set n 1
            }
            set argname [string range $argname 1 end]
            if { ! [info exists as] } {
              set as $argname
            }
            lappend prefix [list upvar $n $argname $as]
            continue
          }
          if { [llength $opts] } {
            while { $opts ne {} } {
              set opts [lassign $opts arg]
              switch -- $arg {
                -default {
                  set opts [lassign $opts default]
                  dict set argopts props $argname def $default
                }
                -name {
                  set opts [lassign $opts name]
                  if { [dict exists $argopts names $name] } {
                    throw error "$name is already defined"
                  }
                  lappend arg_named $name
                  if { ! [info exists named_args] } {
                    lappend named_args $argname
                  } elseif { $argname ni $named_args } {
                    lappend named_args $argname
                  }
                  dict set argopts names $name arg $argname
                  if { $opts ne {} && ! [string equal [string index [lindex $opts 0] 0] -] } {
                    set opts [lassign $opts name_value]
                    dict set argopts names $name val $name_value
                  }
                }
                -switch {
                  while { $opts ne {} && ! [string equal [string index [lindex $opts 0] 0] -] } {
                    set opts [lassign $opts name name_value]
                    if { [dict exists $argopts names $name] } {
                      throw error "$name is already defined"
                    }
                    lappend arg_named $name
                    if { ! [info exists named_args] } {
                      lappend named_args $argname
                    } elseif { $argname ni $named_args } {
                      lappend named_args $argname
                    }
                    dict set argopts names $name [dict create arg $argname val $name_value]
                  }
                }
                -upvar {
                  lappend prefix [list upvar 1 $argname $argname]
                  set include 0
                  continue
                }
              }
            }
          }
          if { $include } {
            lappend newargnames $argname
            if { $arg_named ne {} } {
              dict set argopts props $argname names $arg_named
            }
          }
        }
        if { [info exists named_args] } {
          dict set argopts named $named_args
        }
        if { [info exists prefix] } {
          set body [join [list {*}$prefix $body] \;]
        }
        uplevel 1 [list $command _$proc_name $newargnames $body]
        tailcall $command $proc_name args [join [list \
          [list set definition $argopts] \
          [list set proc_args  $newargnames] \
          [list set command    $proc_name] \
          {tailcall ::decorator::namedargs::call_proc [namespace current] $definition $proc_args $command {} {} {*}$args}
        ] \;]
      }
    }
  }

proc ::decorator::namedargs::call_proc {ns definition proc_args command values nargs args} {
  while { $args ne {} } {
    set args [lassign $args arg]
    if { [string equal [string index $arg 0] -] } {
      set argname [string range $arg 1 end]
      if { [llength $args] && ! [string equal [string index [lindex $args 0] 0] -] } {
        set args [lassign $args name_value]
        if { ! [dict exists $definition names $argname val] } {
          dict set values [dict get $definition names $argname arg] $name_value
        } else {
          dict set values [dict get $definition names $argname arg] [dict get $definition names $argname val]
          lappend nargs $name_value
        }
      } elseif { ! [dict exists $definition names $argname val] } {
        throw error "$argname must have a value"
      } else {
        dict set values [dict get $definition names $argname arg] [dict get $definition names $argname val]
      }
    } else {
      lappend nargs $arg
    }
  }
  set i 0 ; foreach arg $proc_args {
    if { $arg eq "args" } {
      if { [llength $proc_args] == [expr { $i + 1 }] } {
        set proc_args [lrange $proc_args 0 end-1]
        lappend proc_args {*}$nargs
        break
      }
    }
    if { ! [dict exists $definition named] || $arg ni [dict get $definition named] } {
      if { ! [llength $nargs] } {
        throw error "$arg is a required argument"
      } else {
        set nargs [lassign $nargs next_value]
        set proc_args [lreplace $proc_args $i $i $next_value]
      }
    } elseif { [dict exists $values $arg] } {
      set proc_args [lreplace $proc_args $i $i [dict get $values $arg]]
    } elseif { [dict exists $definition props $arg def] } {
      set proc_args [lreplace $proc_args $i $i [dict get $definition props $arg def]]
    } elseif { [dict exists $definition props $arg names] } {
      set names [dict get $definition props $arg names]
      throw error "$arg is a required value but was not defined - it may be defined by the names \"$names\""
    } else {
      throw error "Unkown with $arg"
    }
    incr i
  }
  tailcall ${ns}::_$command {*}$proc_args
}
