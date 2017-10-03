
set tmpath [file normalize [file join \
  [file dirname [info script]] \
  ..
]]

puts $tmpath
::tcl::tm::path add $tmpath

package require forkman

set manager [forkman new]

$manager fork \
  -id one \
  -in 1000 \
  -command {ls -alh /} \
  -onLine {{line meta} {
    puts "Line Received: $line"
  }} \
  -onComplete {meta {
    puts "Completed [dict get $meta -id]"
  }}


vwait __forever__
