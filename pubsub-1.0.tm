package require ensembled

namespace eval pubsub ensembled

variable ::pubsub::subscriptions [dict create]
variable ::pubsub::i 0

# -path
# -id
# -once
# -command
# -async
# -exact
proc pubsub::subscribe args {
  set script [dict get $args -command]
  set path   [dict get $args -path]
  if { [dict exists $args -id] } {
    set id [string map { {:} {} { } {} } [dict get $args -id]]
  } else { set id [pubsub id] }
  
  if { [info commands subscriptions::$id] ne {} } { subscriptions::$id destroy }
  set subscription [subscription create subscriptions::$id $path $script $args]
  if { [dict exists $::pubsub::subscriptions {*}$path @subscriptions] } {
    set subscriptions [dict get $::pubsub::subscriptions {*}$path @subscriptions]
  }
  lappend subscriptions $id
  dict set ::pubsub::subscriptions {*}$path @subscriptions $subscriptions
  return $id
}

proc ::pubsub::id {} {
  return sub_#[incr ::pubsub::i]
}

proc pubsub::dispatch args {
  if { [dict exists $args -data] } {
    set data [dict get $args -data]
  } else { set data {} }
  set path [dict get $args -path]
  set payload [dict create path $path data $data]
  set i 0
  while { $path ne {} } {
    if { [dict exists $::pubsub::subscriptions {*}$path @subscriptions] } {
      foreach id [dict get $::pubsub::subscriptions {*}$path @subscriptions] {
        dict set payload id $id
        incr i [subscriptions::$id execute $payload]
      }
    }
    set path [lrange $path 0 end-1]
  }
  return $i
}

proc pubsub::reset {} {
  set ::pubsub::subscriptions [dict create]
  foreach subscription [info commands subscriptions::*] { $subscription destroy }
}

proc pubsub::unsubscribe args {
  if { [dict exists $args -id] } {
    set id [string map { {:} {} { } {} } [dict get $args -id]]  
    foreach match [info commands subscriptions::$id] {
      $match destroy 
    }
  }
  if { [dict exists $args -path] } {
    pubsub unsubscribe_path [dict get $args -path]
  }
  return
}

proc pubsub::unsubscribe_path path {
  if { [dict exists $::pubsub::subscriptions {*}$path @subscriptions] } {
    foreach id [dict get $::pubsub::subscriptions {*}$path @subscriptions] {
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
  variable PATH SCRIPT OPTS
  constructor args { lassign $args PATH SCRIPT OPTS }
  destructor {
    if { $::pubsub::subscriptions eq {} } { return }
    set ids [dict get $::pubsub::subscriptions {*}$PATH @subscriptions]
    set ids [lsearch -all -inline -not -exact $ids [namespace tail [self]]]
    if { [llength $ids] } {
      dict set ::pubsub::subscriptions {*}$PATH @subscriptions $ids
    } else { dict unset ::pubsub::subscriptions {*}$PATH @subscriptions }
    pubsub cleanup $PATH
  }
  method execute payload { 
    if { [dict exists $OPTS -exact] && [string is true [dict get $OPTS -exact]] } {
      if { $PATH ne [dict get $payload path] } {
        return 0
      } else { dict set payload exact 1 }
    } else { dict set payload exact [expr { $PATH eq [dict get $payload path] }] }
    if { [dict exists $OPTS -async] && [string is true [dict get $OPTS -async]] } {
      my variable after_id
      set after_id [ after 0 [list {*}$SCRIPT $payload] ]
    } else {
      try {
        uplevel #0 $SCRIPT [list $payload]
      } trap CANCEL r {
        throw CANCEL $r
      } on error {} {}
    }
    if { [dict exists $OPTS -once] && [dict get $OPTS -once] } {
      [self] destroy 
    }
    return 1
  }
}