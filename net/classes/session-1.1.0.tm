if 0 {
  @ Session @
    | Provides the API for each http call
    | that is made by the user.
}
::oo::class create ::net::class::Session {}

::oo::define ::net::class::Session {
  variable CONFIG RAW_URL URL ADDRESS PROTOCOL PATH HOST
  variable REQUEST RESPONSE
  variable STATE SOCK STATUS
  variable TIMEOUTS

  constructor args {
    # any [after] id's that should be cancelled
    # when we are removed.
    set TIMEOUTS [dict create]
    set RESPONSE [dict create]
    # $STATE is temporary, right now only used
    # to store error messages
    set STATE    [dict create]
    set REQUEST  [list]
    set SOCK     {}

    lassign $args RAW_URL CONFIG

    my Status VALIDATING
    my Validate
    my Open
  }

  destructor {
    dict for {name id} $TIMEOUTS {
      after cancel $id
    }
    if {[info command [self namespace]::runner] ne {}} {
      catch { [self namespace]::runner CLOSING }
      rename [self namespace]::runner {}
    }
  }
}

::oo::define ::net::class::Session method id {} {
  tailcall namespace tail [self]
}

::oo::define ::net::class::Session method Validate {} {
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

::oo::define ::net::class::Session method Timeout { runner } {
  puts "Runner Timed out! $runner"
  # TODO: Handle timeout - cleanup and alert

}

::oo::define ::net::class::Session method Status {status args} {
  set STATUS $status
  if {[dict exists $CONFIG -onEvent]} {
    try {
      {*}[dict get $CONFIG -onEvent] [self] $STATUS {*}$args
    } on error {result options} {
      puts "onEvent Error: $result"
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
  if {[info exists SOCK] && $SOCK in [chan names]} {
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
      -translation lf \
      -encoding    ascii \
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
  my Status CONNECTING

  lassign $args cmd

  set self [info coroutine]

  # At this point the user will receive the session and
  # our login will move into the asynchronous world.
  dict set   TIMEOUTS startRunner [after 0 $self]
  yield $self
  dict unset TIMEOUTS startRunner

  set SOCK [try $cmd on error {result options} {
    # puts "ERROR OPENING SOCKET!: $result"
    dict set STATE error [list $result $options]
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
      [namespace code [list my Timeout [info coroutine]]]
    ]
  }

  while {$STATUS ni [list CLOSED ERROR TIMEOUT]} {
    set args  [yield [info coroutine]]
    switch -- [lindex $args 0] {
      CLOSING {
        # when we are being closed / removed
        if {$SOCK in [chan names]} {
          catch { chan close $SOCK }
        }
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
      }
      default {
        puts "Unknown $args"
      }
    }
  }
}
