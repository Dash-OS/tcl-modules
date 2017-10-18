# @define - defines a decorator by its first argument which is prefixed with @
#					  commands prefixed with the decorator will do a few things differently
#
#		1. When the command is first built, it will run the -compile body with the command
#			 and raw args that were given
#
#			So if we built a @define @named ...
#
#				@named proc { one two } { ... } --> proc { one two } { ... }
#
#  2. When the command itself is actually called it would first always call the
#     -call hook if defined.  This command would receive the command args, do some
# 		processing or whatever it needs, and return psosibly modified command and
#			args that should be triggered instead.
#	 3. When the command has a value that should be returned to the caller it would
#			called the optionally defined -complete hook and allow modifying the return
#			value if necessary.  Can access previous context(s) if required with uplevel.
package require extend
package require ensembled
namespace eval ::decorator ensembled

proc ::decorator::define {decorator hookargs args} {
  set compiler [dict get $args -compile]
  dict unset args -compile
	tailcall proc \
	  @[string trimleft $decorator @] \
	  [lrange $hookargs 1 end] \
	  [join [list \
	    [list set [lindex $hookargs 0] $args] \
	    $compiler \
	   ] \;]
}

proc ::decorator::call_proc {ns definition proc_args command values nargs args} {
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
      if { ! [llength $nargs] } { throw error "$arg is a required argument" } else {
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

extend info {
  ::proc argspec { named_proc args } {
    set named_proc [uplevel 1 [list namespace which $named_proc]]
    rename ::tailcall ::_tailcall
    try [info body $named_proc] on error {r} {}
    rename ::_tailcall ::tailcall
    return [string trim $definition]
  }

  ::proc namedbody { named_proc } {
    set named_proc [uplevel 1 [list namespace which _$named_proc]]
    tailcall info body $named_proc
  }
}

if 0 {
  @named proc log {
    msg
    { lvl
      -default 2
      -name debug 0
      -name error 1
      -name lvl
      -name info  2
      -switch quiet 0 verbose 9
    }
    { myvar -upvar }
  } {
    puts [list $msg $lvl]
    if {[info exists myvar]} {
      puts $myvar
    }
  }
  set myvar "Some Value"
  log "Hello How Are You!"
}
