if 0 { @ COMPLETELY UNFINISHED! @ }

package require ensembled
package require alias
package require typeof

namespace eval ::modules ensembled
namespace eval ::modules::module {}

if 0 {
  @ modules @
  > import
    | Used to import a module into a scoped script.
}
proc ::import args {
  set request [dict create]
  set types [typeof $args -deep]
  ::modules::parse_list $args request [lindex $types 1]
}

proc ::export args {
  set request [dict create]

  if {[lindex $args 0] eq "default"} {
    dict set request map [lindex $args 1] [lindex $args 0]
  } else {
    set types [typeof $args -deep]
    ::modules::parse_list $args request [lindex $types 1]
  }

  puts "exports $request"
}

if 0 {
  @ ::modules::parse_list $lst
    | Parses the list of exports/imports and returns
    | a normalized dict mapping names to aliases.
  @arg lst {list<imports>|list<exports>}
    May take multiple forms where the following rules are given:
    1. $name as $alias  | import/export a value as another name/alias
    2. $name            | import/export a value by its own name
    3. $name as default | import/export a value as the default value
  @example {

  }
}

#import [list foo] from const
#import foo from const
proc ::modules::parse_list {l rname types {nested false}} {
  upvar 1 $rname request
  set i 0
  set e {}

  puts "parse list"
  puts $types

  if {!$nested} {
    if {[lindex $l 0] eq "from"} {
      set l [lassign $l from module]
      set types [lrange $types 2 end]
      dict set request from $module
    }
  }

  while 1 {
    puts $l
    if {[llength $l] == 0} {
      if {[info exists name]} {
        set_request $name $alias
      }
      break
    }

    set l [lassign $l e]
    set types [lassign $types type]

    puts "$e | $type"

    if {!$nested && [lindex $type 0] ni [list list dict]} {
      set l [lassign $l default]
      dict set request default [string trim $default]
      continue
    } elseif {[llength $e] > 1} {
      parse_list $e request [lindex $type 1] true
      continue
    }

    if {$e eq "from"} {
      if {[info exists name]} {
        set_request $name $alias
      }
      break
    }
    switch -- $i {
      0 {
        incr i
        set name  $e
        set alias $e
        set_request $name $alias
      }
      1 {
        if {$e eq "as"} {
          incr i
        } else {
          set name $e
          set alias $e
        }
      }
      2 {
        set i 0
        set alias $e
        set_request $name $alias
        unset name
      }
    }
  }
  if {$e eq "from" && ![dict exists $request from]} {
    dict set request from $l
  }
  return $request
}

proc ::modules::set_request {key val} {
  upvar 1 request request
  if {$key eq "default" && $val ne "default"} {
    if {[dict exists $request default]} {
      throw MODULES_DEFAULT_INVARIANT "only one module may be set as default"
    }
    dict set request default [string trim $val]
  } else {
    dict set request map $key [string trim $val]
  }
}

#
# if 0 {
#   override locally called [source] calls to provide
#   the necessary scope handling.
# }
# proc ::modules::source path {
#
# }
#
# if 0 {
#   @example
#   {
#     import const from "const"
#
#     const v 1
#
#     puts $v ; #
#
#     proc myproc {} {
#       puts yay
#     }
#
#     export {
#       myproc as default
#       myproc as name
#       myproc
#     }
#   }
# }
