package require ensembled

namespace eval pubsub ensembled

variable ::pubsub::subscriptions [dict create]

proc pubsub::subscribe {id args} {
  set script [lindex $args end]
  set path   [lrange $args 0 end-1]
  set id [string map { {:} {} { } {} } $id]
  if { [info commands subscriptions::$id] ne {} } { subscriptions::$id destroy }
  set subscription [subscription create subscriptions::$id $path $script]
  if { [dict exists $::pubsub::subscriptions {*}$path @subscriptions] } {
    set subscriptions [dict get $::pubsub::subscriptions {*}$path @subscriptions]
  }
  lappend subscriptions $id
  dict set ::pubsub::subscriptions {*}$path @subscriptions $subscriptions
}

proc pubsub::dispatch {data args} {
  if { [dict exists $::pubsub::subscriptions {*}$args @subscriptions] } {
    foreach id [dict get $::pubsub::subscriptions {*}$args @subscriptions] {
      subscriptions::$id execute $data
      incr i
    }
    return $i
  } else { return 0 }
}

proc pubsub::reset {} {
  set ::pubsub::subscriptions [dict create]
  foreach subscription [info commands subscriptions::*] { $subscription destroy }
}

proc pubsub::unsubscribe id {
  set id [string map { {:} {} { } {} } $id]
  if { [info commands subscriptions::$id] ne {} } { subscriptions::$id destroy }
}

proc pubsub::unsubscribe_path args {
  if { [dict exists $::pubsub::subscriptions {*}$args @subscriptions] } {
    foreach id [dict get $::pubsub::subscriptions {*}$args @subscriptions] {
      catch { subscriptions::$id destroy }
    } 
  }
}

proc pubsub::cleanup path {
  while {$path ne {}} {
    if { [dict exists $::pubsub::subscriptions {*}$path] } {
      if { [dict get $::pubsub::subscriptions {*}$path] eq {} } {
        dict unset ::pubsub::subscriptions {*}$path
        set path [lrange $path 0 end-1]
      } else { break }
    } else { break }
  }
}

proc pubsub::trigger {id args} {
  set id [string map { {::} {_} { } {_} } $id]
  if { [info commands subscriptions::$id] ne {} } { 
    return [ subscriptions::$id execute {*}$args]
  }
  return
}

::oo::class create ::pubsub::subscription {
  variable PATH SCRIPT
  constructor args { lassign $args PATH SCRIPT }
  destructor {
    if { $::pubsub::subscriptions eq {} } { return }
    set ids [dict get $::pubsub::subscriptions {*}$PATH @subscriptions]
    set ids [lsearch -all -inline -not -exact $ids [namespace tail [self]]]
    if { [llength $ids] } {
      dict set ::pubsub::subscriptions {*}$PATH @subscriptions $ids
    } else { dict unset ::pubsub::subscriptions {*}$PATH @subscriptions }
    pubsub cleanup $PATH
  }
  method execute args { catch { uplevel #0 $SCRIPT $args } }
}