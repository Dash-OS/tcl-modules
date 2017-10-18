package require decorator

namespace eval ::decorator::namedargs {}

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
