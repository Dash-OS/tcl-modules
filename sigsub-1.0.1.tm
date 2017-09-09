if 0 {
  @ sigsub
    > IMPORTANT <
      | It is most likely this will not work without changing
      | a few things in your setup.  Within ours we have to
      | load the package using "load" instead of package require.
      |
      | If you have the signal package installed then you
  @package @ sigsub {export}
    | Signal Handling through the [pubsub] command provided
    | within tcl-modules.
    |
    | If no listeners are subscribed, the process is exited
    | immediately.
  @dependencies
    1. > tclsignal @ https://github.com/wjoye/tclsignal
    1. > pubsub    @ https://github.com/Dash-OS/tcl-modules
    2. > ensembled @ https://github.com/Dash-OS/tcl-modules
  @reference
    | https://github.com/wjoye/tclsignal/blob/master/doc/sig.announce.1.4

    > Signal Handling <
      When a registered signal occurs, we will check to see if any
      subscribers received the event.  If not, the process
      will be exited immediately.

      If subscribers do receive the event, an exit will be
      scheduled automatically for 5 seconds in the future
      to allow asynchronous subscriptions a chance to
      execute before we exit.

      A synchronous subscription may throw IGNORE_SIGNAL
      to stop the exit process if desired.

      Additionally, calling [sigsub interrupt] will also
      cancel the exit process.
  @example
    {
      package require sigsub

      # register signal handlers (registerAsync for -async)
      sigsub register SIGINT SIGHUP

      # create some subscribers to the signals
      pubsub subscribe -command handleAnySignal -path [list signal]
      pubsub subscribe -command handleSIGINT    -path [list signal SIGINT]
      pubsub subscribe -command handleSIGHUP    -path [list signal SIGHUP]
    }

  @type > Signal {string|number}
    | A Signal can be provided as either a string in its common form
    | (example: SIGINT, SIGHUP) or as the signal number.
}

package require pubsub
package require ensembled
package require signal

namespace eval ::sigsub {ensembled}

variable ::sigsub::after_id {}

variable ::sigsub::delay 5000

if 0 {
  @ ::sigsub::receive {Signal}
    | Receives a signal event and dispatches to potential
    | [pubsub] subscribers.
}
proc ::sigsub::receive signal {
  if {$::sigsub::after_id eq {}} {
    set ::sigsub::after_id [after $::sigsub::delay [list \
      ::apply [list {} {exit 0}]
    ]]
  }
  try {
    set listeners [pubsub dispatch \
      -path [list signal $signal] \
      -data $signal
    ]
    if {$listeners == 0} {exit 0}
  } trap IGNORE_SIGNAL {} {
    sigsub interrupt
  } on error {} {
    exit 0
  }
}

if 0 {
  @ sigsub interrupt
    | Allows another way of interrupting the exit process.
    | When called it will cancel the [after $delay exit] procedure.
  @returns {boolean}
    Indicates whether an exit process was interrupted or not.
}
proc ::sigsub::interrupt {} {
  if {$::sigsub::after_id ne {}} {
    after cancel $::sigsub::after_id
    set ::sigsub::after_id {}
    return true
  } else { return false }
}

if 0 {
  @ sigsub register > ?...signals?
    | A list of signals to register for subscription.
  @args {list<Signal>}
}
proc ::sigsub::register args {
  foreach signal $args {
    ::signal add [string toupper $signal] [list \
      ::apply [list signal {::sigsub::receive $signal} $signal]
    ]
  }
}

if 0 {
  @ sigsub registerAsync > ?...signals?
    | Same as register except adds the -async flag (read reference docs)
}
proc ::sigsub::registerAsync args {
  foreach signal $args {
    ::signal add [string toupper $signal] [list \
      ::apply [list signal {::sigsub::receive $signal} $signal]
    ] -async
  }
}
