if 0 {
  > forkit
    | A background task manager combining various
    | tcl-modules to provide a powerful api for managing
    | forked processes.

  > [task]
    | The core method by which this works is by extending
    | the [task] command.  It starts by calling [task] with
    | the given args and runs the [-command] when completed.

  @example
  {
    set manager [forkman new]

    # standard commands with no callbacks/hooks
    $manager -id one -in 1000 -command {tclsh ./one.tcl}

    $manager -id two -command {tclsh ./two.tcl} \
      -onLine {{line meta} {
        puts "Two Line: $line"
      }} \
      -onComplete {meta {
        puts "Completed ID [dict get $meta -id]"
      }}
  }
}

package require task
package require callback

::oo::class create forkman {
  variable I
  variable FORKS

  constructor args {
    set I 0
    set FORKS [dict create]
  }

  method fork args {
    incr I
    set nargs [list]
    set cmd [dict get $args -command]
    if {[dict exists $args -id]} {
      set id [dict get $args -id]
    } else {
      set id fork#$I
      dict set args -id $id
    }
    if {[dict exists $args -onLine]} {
      lappend nargs -onLine [dict get $args -onLine]
      dict unset args -onLine
    }
    if {[dict exists $args -onComplete]} {
      lappend nargs -onComplete [dict get $args -onComplete]
      dict unset args -onComplete
    }
    dict unset args -command
    tailcall task {*}$args -command [callback my Execute $cmd {*}$args {*}$nargs]
  }

  method cancel {id args} {
    task -cancel $id {*}$args
  }

  method Execute {cmd args} {
    set fd [open |[list {*}$cmd]]

    dict set FORKS $fd [dict create {*}$args -command $cmd -manager [self]]

    chan configure $fd -blocking 0 -buffering line
    chan event $fd readable [callback my Read $fd]
  }

  method Read fd {
    # puts "Read $fd"
    set meta [dict get $FORKS $fd]
    if {[dict exists $meta response]} {
      set response [dict get $meta response]
    } else {
      set response [list]
    }

    if {[chan eof $fd]} {
      my Complete $fd
      return
    }

    while {[chan gets $fd line] >= 0} {
      lappend response $line
      if {[dict exists $meta -onLine]} {
        dict set meta response $response
        set onLine [dict get $meta -onLine]
        try [list ::apply [list {*}$onLine] $line $meta] on error {result options} {
          puts stderr "onLine Error: $result"
          puts stderr $options
        }
      }
    }

    dict set meta response $response
    dict set FORKS $fd $meta
  }

  method Complete fd {
    set meta [dict get $FORKS $fd]
    chan close $fd
    if {[dict exists $meta -onComplete]} {
      set onComplete [dict get $meta -onComplete]
      try [list ::apply [list {*}$onComplete] $meta] on error {result options} {
        puts stderr "onComplete Error: $result"
        puts stderr $options
      }
    }
  }

}
