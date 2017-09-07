package require ensembled
package require callback

namespace eval pubsub {ensembled}

variable ::pubsub::subscriptions [dict create]
variable ::pubsub::i 0

if 0 {
  @type > SubscriberID {mixed}
    | A string representing the unique subscriber id that was
    | created (or the id that was passed with -id when calling).
    |
    | This can be used to unsubscribe in the future without knowing
    | what path the subscription is currently attached to.


  @ pubsub subscribe @
    | Subscribes to a channel so that pushes to the given channel
    | will be sent to the subscribed procedures.
  @args {list<-opts>}
    @opt -command {*proc*}
      Required argument which indicates which command should be
      called when a dispatch matches.

      Tip: If a command is executed synchronously, throwing CANCEL
           within the execution of the command will remove the
           subscription.
    @opt -path {*list<mixed>*}
      Required argument which is a list giving a path for the
      subscription.  These work like categories and are used to
      match when dispatching.
      @example {-path [list system alerts]}
        In this example, we receive alerts on "system" or "system alerts"
    @opt -id
      Optionally provide an id to be used for the subscription.
      If multiple subscriptions occur with the same id, all previous
      id's will be removed before the new subscription is added.
    @opt -once
      If provided, indicates that the subscription should only execute
      once before it is automatically removed.
    @opt -async
      Execution is done asynchronously
    @opt -exact
      Path must match exactly when provided.
    @opt -on {?dict<event, proc>?}
      An optional dict mapping supported events to a proc
      that should be called when the event occurs.
      @key error
        When an error occurs during execution of the command.
  @returns {SubscriberID}
}
proc pubsub::subscribe args {
  if {![dict exists $args -command] || ![dict exists $args -path]} {
    throw PUBSUB_INVALID_ARGS \
      "pubsub subscribe expects -command and -path args"
  }

  set script [dict get $args -command]
  set path   [dict get $args -path]

  if { [dict exists $args -id] } {
    set id [string map { {:} {} { } {} } [dict get $args -id]]
  } else { set id [pubsub id] }

  if { [info commands subscriptions::$id] ne {} } {
    subscriptions::$id destroy
  }

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

if 0 {
  @ pubsub dispatch @
    | Dispatch a message that will be execute if anyone is listening
    | to the given path.
  @args {list<-opts>}
    @opt -path {list<string>}
      What path to send our event to?
    @opt -data {any}
      The data to dispatch to the listeners
  @returns {entier}
    Returns the total matching subscribers.
  @example
  {
    set received [pubsub dispatch -path [list system alerts] -data [list cpu > 80]]
  }
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
      set subscribers       [dict get $::pubsub::subscriptions {*}$path @subscriptions]
      set total_subscribers [llength $subscribers]
      foreach id $subscribers {
        dict set payload id $id
        dict set payload subscribers $total_subscribers
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
    if { $::pubsub::subscriptions eq {} } {
      return
    }
    set ids [dict get $::pubsub::subscriptions {*}$PATH @subscriptions]
    set ids [lsearch -all -inline -not -exact $ids [namespace tail [self]]]
    if { [llength $ids] } {
      dict set ::pubsub::subscriptions {*}$PATH @subscriptions $ids
    } else {
      dict unset ::pubsub::subscriptions {*}$PATH @subscriptions
    }
    if {[dict exists $OPTS -async] && [string is true -strict [dict get $OPTS -async]]} {
      my variable after_id
      if {[info exists after_id]} {
        after cancel $after_id
      }
    }
    ::pubsub cleanup $PATH
  }
  method execute payload {
    if { [dict exists $OPTS -exact] && [string is true -strict [dict get $OPTS -exact]] } {
      if { $PATH ne [dict get $payload path] } {
        return 0
      } else { dict set payload exact 1 }
    } else { dict set payload exact [expr { $PATH eq [dict get $payload path] }] }
    if { [dict exists $OPTS -async] && [string is true -strict [dict get $OPTS -async]] } {
      my variable after_id
      set after_id [after 0 \
        [callback my execute_async $payload]
      ]
    } else {
      try {
        uplevel #0 $SCRIPT [list $payload]
      } trap CANCEL r {
        [self] destroy
        return 0
      } on error {result options} {
        if {[dict exists $OPTS -on error]} {
          set cmd [dict get $OPTS -on error]
          try {
            uplevel #0 $cmd [list [dict merge $payload [dict create \
              result       $result \
              options      $options \
              subscription [self]
            ]]]
          } trap CANCEL r {
            [self] destroy
            return 0
          }
        } else {
          set code [dict get $options -errorcode]
          throw $code $result
        }
      }
    }
    if { [dict exists $OPTS -once] && [string is true -strict [dict get $OPTS -once]] } {
      [self] destroy
    }
    return 1
  }
  method execute_async payload {
    try {
      uplevel #0 $SCRIPT [list $payload]
    } trap CANCEL r {
      [self] destroy
    } on error {result options} {
      if {[dict exists $OPTS -on error]} {
        set cmd [dict get $OPTS -on error]
        try {
          uplevel #0 $cmd [list [dict merge $payload [dict create \
            result $result \
            options $options \
            subscription [self]
          ]]]
        } trap CANCEL r {
          [self] destroy
        }
      }
    }
  }
}
