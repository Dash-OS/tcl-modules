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

namespace eval ::decorator {}


proc @define { decorator hookargs args } {
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

@define @named { definition command args } \
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
              if { $n eq {} } { set n 1 }
            } else { set n 1 }
            set argname [string range $argname 1 end]
            if { ! [info exists as] } { set as $argname }
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
                  if { [dict exists $argopts names $name] } { throw error "$name is already defined" }
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
                    if { [dict exists $argopts names $name] } { throw error "$name is already defined" }
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
            if { $arg_named ne {} } { dict set argopts props $argname names $arg_named }
          }
        }
        if { [info exists named_args] } { dict set argopts named $named_args }
        if { [info exists prefix] } { set body [join [list {*}$prefix $body] \;] }
        uplevel 1 [list $command _$proc_name $newargnames $body]
        tailcall $command $proc_name args [join [list \
          [list set definition $argopts] \
          [list set proc_args $newargnames] \
          [list set command $proc_name] \
          {tailcall ::decorator::call_proc [namespace current] $definition $proc_args $command {} {} {*}$args}
        ] \;]
      }
    }
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
    } else { lappend nargs $arg }
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
  puts call
  tailcall ${ns}::_$command {*}$proc_args
}

extend info {
  proc argspec { named_proc args } {
    set named_proc [uplevel 1 [list namespace which $named_proc]]
    rename ::tailcall ::_tailcall
    try [info body $named_proc] on error {} {}
    rename ::_tailcall ::tailcall
    return [string trim $definition]
  }
  
  proc namedbody { named_proc } {
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
    puts $myvar
  }  
}