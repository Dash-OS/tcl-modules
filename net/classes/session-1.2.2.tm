if 0 {
  @ Session @
    | Provides the API for each http call
    | that is made by the user.
}
::oo::class create ::net::class::Session {}

::oo::define ::net::class::Session {
  # The template object which is creating the session,
  # used to copy the  object when required.
  variable TEMPLATE
  # When we are cloned for reuse, this will include the
  # object that created us.
  variable PARENT
  variable CONFIG RAW_URL URL ADDRESS PROTOCOL PATH HOST
  variable REQUEST RESPONSE
  variable STATE SOCK STATUS
  variable TIMEOUTS
}

::oo::define ::net::class::Session constructor args {
  lassign $args TEMPLATE RAW_URL CONFIG
  my Initialize
  my Validate
  my send
}

::oo::define ::net::class::Session destructor {
  if {[info exists TIMEOUTS]} {
    dict for {name id} $TIMEOUTS {
      after cancel $id
    }
  }
  if {[info command [self namespace]::runner] ne {}} {
    # alert the runner that we are closing
    catch { [self namespace]::runner CLOSING }
    # this should not be required considering its within
    # our namespace and that will be deleted when finished,
    # but lets just be explicit shall we?
    catch { rename [self namespace]::runner {} }
  }
  # Just to be sure, close the socket if for any reason
  # it did not get handled by the runner.
  my Close
  # Once
}

::oo::define ::net::class::Session method Initialize {} {
  # any [after] id's that should be cancelled
  # when we are removed.
  set TIMEOUTS [dict create]
  set RESPONSE [dict create]
  set REQUEST  [dict create]
  # $STATE is temporary, right now only used
  # to store error messages
  set STATE    [dict create]
  set SOCK     {}
  set STATUS   INITIALIZED
}

# can probably remove this -- not really useful for anything
# but will leave it here for now.
::oo::define ::net::class::Session method id {} {
  tailcall namespace tail [self]
}

::oo::define ::net::class::Session method resend args {
  # There may be times that reusing a session is a desired effect.
  # In this case, the send method will copy this object
  set child [::oo::copy [self] ::net::sessions::[$TEMPLATE nextid]]
  $child send {*}$args
  return $child
}

::oo::define ::net::class::Session method wait args {
  if {[info coroutine] ne {}} {
    # If we are within a coroutine then [wait] can
    # forego the need to create nested vwaits
    return [yieldto [self namespace]::runner [list WAIT [info coroutine]]]]
  } else {
    # When we are not within a coroutine already, we will need to
    # depend upon vwait to provide an implementation of [wait].
    #
    # We will create a coroutine which will await a response asynchronously.
    # each "waiter" is called.  We are not putting particular focus on this
    # being done with high performance - use the other method if possible.
    namespace eval [namespace current]::waiters {}
    set id [expr {[llength [info vars [namespace current]::waiters::*]] + 1}]
    set waiter [namespace current]::waiters::$id
    set $waiter 0
    # allow setting a separate timeout during manual [waits]
    if {"-timeout" in $args} {
      dict set TIMEOUTS $waiter \
        [after [dict get $args -timeout] [list set $waiter timeout]]
    }
    vwait $waiter
    if {$STATUS ne "COMPLETE"} {
      return TIMEOUT
    } else {
      return $RESPONSE
    }
  }
}

::oo::define ::net::class::Session method send args {
  if {[llength $args]} {
    # if args are defined during this command, we will
    # need to re-run validation (which also removes most of the
    # benefit to using the clone option)
    if {[llength $args] == 1} {
      lassign $args args
    }
    set CONFIG [dict merge $CONFIG $args]
    my Validate
  }
  my Open
}

::oo::define ::net::class::Session method response args {
  if {[llength $args]} {
    return [dict get $RESPONSE {*}$args]
  }
  return $RESPONSE
}

::oo::define ::net::class::Session method props args {
  set props [list]
  foreach arg $args {
    lappend props [set [string toupper $arg]]
  }
  return $props
}

::oo::define ::net::class::Session method <cloned> parent {
  set PARENT $parent
  my Initialize
  # Grab the configuration and state from our parent
  lassign [$PARENT props CONFIG REQUEST RAW_URL URL ADDRESS PROTOCOL PATH HOST TEMPLATE] \
    CONFIG REQUEST RAW_URL URL ADDRESS PROTOCOL PATH HOST TEMPLATE
  my Status CLONED
}

::oo::define ::net::class::Session method Validate {} {
  my Status VALIDATING
  set config [dict merge $::net::config $CONFIG]
  # if {[dict get $config -validate]} {
  #   proptypes $config {
  #     -strict         bool
  #     -binary         {bool false}
  #     -blocksize      {entier false}
  #     -queryblocksize {entier false}
  #     -charset        string
  #     -validate       {bool false}
  #     -timeout        {entier false}
  #     -query          {any false}
  #     -body           {any false}
  #     -protocol       {any false}
  #   }
  # }
  set descriptor [::net::validate $RAW_URL $config]
  dict with descriptor {}
}

::oo::define ::net::class::Session method Open {} {
  my Status OPENING
  lappend cmd [lindex $PROTOCOL 1] -async
  if {[dict exists $CONFIG -myaddr]} {
    lappend cmd -myaddr [dict get $CONFIG -myaddr]
  }
  lappend cmd {*}$ADDRESS
  tailcall coroutine [self namespace]::runner my Runner $cmd
}

::oo::define ::net::class::Session method Close {} {
  if {$SOCK ne {} && $SOCK in [chan names]} {
    catch { chan close $SOCK }
    set SOCK {}
  }
  my Status CLOSED
}

::oo::define ::net::class::Session method Timeout {} {
  if {[info commands [self namespace]::runner] ne {}} {
    # let the runner report the timeout event if possible
    # so the onEvent call runs in the coro scope
    runner TIMEOUT
  } elseif {$STATUS ni [list COMPLETE]} {
    # this should really never happen -- sanity check :)
    my Status TIMEOUT
    my Close
  }
}

::oo::define ::net::class::Session method Status {status args} {
  if {$status ne $STATUS} {
    set STATUS $status
    ## TODO: Change this to the planned / better event dispatch
    if {[dict exists $CONFIG -command]} {
      try {
        {*}[dict get $CONFIG -command] [self]
      } on error {result options} {
        puts stderr "onCommand Error: $result"
      }
    }
    if {[dict exists $CONFIG -onEvent]} {
      try {
        # run the event from the callers scope
        tailcall {*}[dict get $CONFIG -onEvent] [self] $STATUS {*}$args
      } on error {result options} {
        puts stderr "onEvent Error: $result"
      }
    }
  }
}

::oo::define ::net::class::Session method BuildRequest {} {
  set REQUEST [list]
  # $METHOD $PATH HTTP/$VERSION \r\n
  lappend REQUEST \
    "[string toupper [dict get $CONFIG -method]] $PATH HTTP/[dict get $CONFIG -version]"
  # $headerKey: $headerValue \r\n
  foreach {hdr val} [dict get $CONFIG -headers] {
    lappend REQUEST "${hdr}: $val"
  }
  # \r\n
  lappend REQUEST {}
}

::oo::define ::net::class::Session method SendRequest {} {
  if {$SOCK in [chan names]} {
    if {[llength $REQUEST] == 0} {
      my BuildRequest
      if {[llength $REQUEST] == 0 } {
        # failed to build request
        # TODO: handle error message here.
        return
      }
    }

    chan configure $SOCK -translation binary

    puts $SOCK [join $REQUEST \r\n]

    if {[dict exists $CONFIG -body]} {
      chan configure  $SOCK -translation {auto binary}
      puts -nonewline $SOCK [dict get $CONFIG -body]
    }

    chan configure $SOCK \
      -translation {auto crlf} \
      -encoding    [dict get $CONFIG -encoding] \
      -buffering   line

    chan flush $SOCK
  } else {
    tailcall return \
      -code error \
      -errorCode [list HTTP SESSION SEND_REQUEST SOCKET_NOT_FOUND] \
      " tried to send a request to a socket which does not exist or has not yet been opened."
  }
}

::oo::define ::net::class::Session method Runner args {
  lassign $args cmd
  set waiters [list]

  # At this point the user will receive the session and
  # our login will move into the asynchronous world.
  dict set TIMEOUTS startRunner [after 0 [info coroutine] [list CONTINUE]]

  while {"CONTINUE" ni $args} {
    if {"WAIT" in $args} {
      lappend waiters [lindex $args 1]
    }
    set args [yield [info coroutine]]
  }

  my Status CONNECTING

  set SOCK [try $cmd on error {result options} {
    # puts "ERROR OPENING SOCKET!: $result"
    dict set STATE error [list $STATUS $result $options]
    my Status ERROR
    return
  }]

  chan configure $SOCK \
    -translation {auto crlf} \
    -blocking    0 \
    -buffering   full \
    -buffersize  [dict get $CONFIG -buffersize] \
    -encoding    [dict get $CONFIG -encoding]

  chan event $SOCK writable [list [info coroutine] CONNECTED]
  chan event $SOCK readable [list [info coroutine] HEADER]

  if {[dict exists $CONFIG -timeout]} {
    dict set TIMEOUTS timeout [after [dict get $CONFIG -timeout] \
      [namespace code [list my Timeout]]
    ]
  }

  while {$STATUS ni [list CLOSED COMPLETE ERROR TIMEOUT]} {
    try {
      set args  [yield [info coroutine]]
      switch -- [lindex $args 0] {
        WAIT {
          if {$STATUS eq "COMPLETE"} {
            [lindex $args 1] $RESPONSE
          } else {
            lappend waiters [lindex $args 1]
          }
        }
        TIMEOUT {
          # Handle Timeout
          my Status TIMEOUT
          my Close
        }
        CLOSING {
          # when we are being closed / removed
          my Close
        }
        CONNECTED {
          chan event $SOCK writable {}
          my Status CONNECTED
          my SendRequest
        }
        HEADER {
          while {![chan eof $SOCK] && [chan gets $SOCK header] >= 0} {
            set header [string trim $header]
            if {$header eq {}} {
              # HEADER parsing has completed, change the event to report
              # to our DATA handler.
              chan configure $SOCK -buffering full -translation binary
              chan event $SOCK readable [list [info coroutine] DATA]
              break
            } elseif {![dict exists $RESPONSE state]} {
              # TODO: Probably a better way of doing this which would
              #       be faster internally.
              set header [string trimleft $header " HTTP/"]
              dict set RESPONSE state [dict create \
                version  [lindex $header 0] \
                code     [lindex $header 1] \
                status   [lindex $header 2]
              ]
            } else {
              set colonIdx [string first : $header]
              dict set RESPONSE headers \
                [string tolower [string range $header 0 [expr {$colonIdx - 1}]]] \
                [string trim [string range $header [expr {$colonIdx + 1}] end]]
            }
          }
        }
        DATA {
          # TODO: handle chunk sizing
          set data [read $SOCK]

          dict append RESPONSE data $data
          # This is just a temporary handling while testing,
          # need to analyze the best method for handling
          # keep alive sockets and the like.
          if {[chan eof $SOCK]} {
            chan close $SOCK
            set RESPONSE [::net::parse $RESPONSE]
            my Status COMPLETE
          }
          # elseif {[dict exists $RESPONSE headers content-length]} {
          #   set received_length [string length [dict get $RESPONSE data]]
          #   if {[dict get $RESPONSE headers content-length] < $received_length} {
          #     # We have too much data!
          #   }
          # }
        }
        default {
          puts "Unknown $args"
        }
      }
    } on error {result options} {
      # Report the error during processing to the caller
      dict set STATE error [list $STATUS $result $options]
      my Status ERROR
      break
    }
  }

  if {[dict exists $TIMEOUTS timeout]} {
    after cancel [dict get $TIMEOUTS timeout]
    dict unset TIMEOUTS timeout
  }

  if {$STATUS ni [list COMPLETE ERROR TIMEOUT]} {
    my Status COMPLETE
  }

  foreach waiter $waiters {
    puts "Waking up Waiter! $waiter"
    {*}$waiter $RESPONSE
  }

  foreach waitvar [info vars [namespace current]::waiters::*] {
    set $waitvar 1
  }
}


# proc report args {
#   puts "HTTP REPORT: $args"
#   uplevel 1 {
#     puts "Vars [info vars]"
#     puts [info exists REQUEST]
#   }
# }
#
# proc test {{url http://www.google.com}} {
#   set session [net call $url -timeout 15000 -onEvent ::report]
#   puts "Waiting? $session"
#
#   set response [$session wait]
#
#   puts "Wait Response? [string length $response]"
#
#   puts "\n\nWAITING DONE\n\n"
# }
#
# proc testcoro {} {
#   coroutine mycoro test
#   puts "Coro Created!"
#   after 5000 { set i 0 }; vwait i
#
# }
#
# proc testnormal {} {
#   test
#   # after 5000 { set i 0 }; vwait i
#
# }
#
# proc spawncoros
