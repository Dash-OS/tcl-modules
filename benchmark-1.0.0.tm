package require extend::dict
package require ensembled
namespace eval benchmark ensembled

if 0 {
  @ benchmark commands | $args
    A simple utility to quickly check the difference between
    different commands.

    It saves each invocation so that if it is called additional times
    without any arguments it will re-run the given group while reversing
    the order it runs them in.  In the future may use shuffle here since
    various things may affect the speed based on what order it runs in.

    NOTE: May be doing something incorrect there since it does appear some
          situations the ordering can greatly affect the result.

    -times $times | optional number of times to run (default: 1000)
    @args {list<commands>}
    @example
    {
      package require benchmark

      set dict [dict create foo bar]

      proc one {} {
        if {[dict exists $::dict foo]} {
          return [dict get $::dict foo]
        }
      }
      proc two {} {
        dict get $::dict foo
      }

      benchmark commands one two
      # benchmark commands
      # ^ now would run [benchmark commands two one]
      # ----------------------------------
      # Winner:
      # one
      # ----------------------------------
      #
      #  RESULT 1 | Arg 1 | 0.9 avg. microseconds
      # two
      #  RESULT 2 | Arg 0 | 1.139 avg. microseconds | 26.56% slower
      # one
    }
}
proc ::benchmark::commands args {
  variable history
  if {[llength $args] == 0} {
    set args [lreverse [dict get $history commands]]
  }

  dict set history commands $args

  if {"-times" in $args} {
    set args [lassign $args -times times]
  } else { set times 1000 }

  set results [dict create]

  set i 0
  foreach cmd $args {
    set result [time $cmd $times]
    dict set results $i [lindex $result 0]
    incr i
  }

  set results  [dict sort values $results]
  set keys     [dict keys $results]
  set winnerMS [dict get $results [lindex $keys 0]]

  puts "
----------------------------------
Winner:
[lindex $args [lindex $keys 0]]
----------------------------------
  "

  set i 1
  dict for {k v} $results {
    puts -nonewline " RESULT ${i} | Arg ${k} | ${v} avg. microseconds"
    if {$i > 1} {
      puts " | [::format %.2f [expr { abs(( ($winnerMS - $v) / $winnerMS ) * 100) }]]% slower"
    } else {
      puts ""
    }
    puts [lindex $args $k]
    incr i
  }
  return $results
}

# package require json_tools
#
# proc one {} {
#   ::rl_json::json get {{
#     "foo": "bar",
#     "one": {
#       "ok": {
#         "fine": ["one", "two", "three"]
#       }
#     }
#   }}
# }
#
# proc two {} {
#   ::yajl::json2dict {{
#     "foo": "bar",
#     "one": {
#       "ok": {
#         "fine": ["one", "two", "three"]
#       }
#     }
#   }}
# }
#
# benchmark commands one two
