package require cmdlist

namespace eval ::coro {
  namespace ensemble create
  namespace export {[a-z]*}
}

# provides a unique id / name when called by incrementing a ns variable by one each
# time it is called in a similar fashion to after#1 after#2 after#3
# optionally provide a prefix to change from coro#1 to $prefix#1
proc ::coro::id { {prefix coro} } {
  return ${prefix}#[incr [namespace current]::i]
}

# expected to be called within a TclOO Object, this will create a coroutine
# in the objects namespace so that it is run in the same way any other method
# would be run. methods can then call it by name as it is added to the namespace.
proc ::coro::method { name method args } {
  set ns [uplevel 1 {self namespace}]
  tailcall coroutine ${ns}::$name ${ns}::my $method {*}$args
}

# sleep for $n (0) then wake itself up again.  useful for scheduling itself
# independent of its creator.
proc ::coro::sleep { {n 0} } {
  after $n [list catch [list [info coroutine]]]
  tailcall yield [info coroutine]
}

# inject a script into a coroutine to be executed upon the next time it wakes
proc ::coro::inject { coro script } {
  tailcall ::tcl::unsupported::inject $coro try $script
}

# inject a script into a coroutine and return the result.  evaluates in the callers
# context so we resolve as the programmer is likely expecting.
#
# this is slightly different than inject in that it executes the script automatically, pauses
# the execution automatically after the script is ran, and runs within a try block so we
# catch any errors.  In the case of an error we do nothing at this time.
#
# As an example, if we want to get the value of a variable in the coro context:
# set value [coro eval mycoro { set myvar }]
proc ::coro::eval { coro script } {
  uplevel 1 [format {%s;%s} \
    [list ::tcl::unsupported::inject $coro try [format { yield [try {%s} on error {} {}] } $script]] \
    $coro
  ]
}

# coro yields one two three -> yield [list one two three]
proc ::coro::yields args {
  tailcall yield $args
}

# Runs a simple check to see if the coroutine exists or not.
proc ::coro::exists coro {
  expr {[info command $coro] ne {}}
}

# Attempts to determine if the given coroutine is the coroutine we are currently in.
# This should generally not be needed and we should know this but it can be useful
# in certain situations.
proc ::coro::running { coro } { string match *$coro [info coroutine] }

if 0 {
  @ coro create @
    similar to the standard coroutine command with the ability to
    also create asynchronous coroutines which push themselves into
    the background, yielding their name to the caller.
  @arg -async {optional}
    When defined, pushes the coroutine into the background
    to be serviced by the event loop.
  @arg name {string}
    The name to be used for the coroutine
  @args args
    The command and any args to be used when calling the
    command.

  NOTE: To see an example, view the example below for [coro defer]
}
proc ::coro::create args {
  set args [lassign $args name]
  if {$name eq "-async"} {
    set async true
    set args [lassign $args name]
  }
  if {[info exists async]} {
    tailcall coroutine $name ::apply {{cmd} {
      after 0 [list catch [list [info coroutine]]]
      yield   [info coroutine]
      try $cmd
    }} $args
  } else {
    tailcall coroutine $name {*}$args
  }
}

if 0 {
  @ coro defer ?-with $vars? ?-scoped? $script {*}$args @
    defers the execution of $script until the coroutine completes.
    Optionally bring in vars from the current scope with -with $vars
    or -scoped.

    @arg -with {list<varname>}
      A list of vars to bring into the scope to be used by $script
    @arg -scoped
      If defined, takes [info locals] from scope at the time of execution
      and makes them available to the script
    @arg script {script}
      The script to execute when the defer executes
    @args args {list<values>}
      When args are provided after the script, they are made available
      as part of the $args value to the script.  Should the main script
      also have $args defined (and brought into scope) then the value
      of $args becomes {list<...$deferargs ...$args>}

    @returns unsubscribe {script}

    @example
      {
        proc myproc args {
          set v baz
          set defer [coro defer -with [list v args] {
            puts "Coroutine Complete!"
            puts "v:    $v"
            puts "Args: $args"
          } qux]
          puts "Continue"
          # remove defer if needed
          # try $defer || {*}$defer
        }
        coro create mycoro myproc foo
      } >
      |  Continue
      |  Coroutine Complete!
      |  v:    baz
      |  Args: qux foo

}
proc ::coro::defer args {
  set args  [lassign $args script]

  while {[string match -* $script]} {
    switch -- $script {
      -with   { set args [lassign $args with] }
      -scoped { set with [uplevel 1 {info locals}] }
    }
    set args [lassign $args script]
  }

  if {[info exists with]} {
    foreach v $with[set with [dict create]] {
      dict set with $v [uplevel 1 [list set $v]]
    }
  } else { set with [dict create] }

  set trace [list apply [list {with _args args} [cmdlist \
    {
      unset args
      dict with with {}
      if {[info exists args]} {
        set args [list {*}${_args} {*}$args]
      } else {
        set args ${_args}
      }
      unset _args
      unset with
    } \
    $script
  ]] $with $args]

  uplevel 1 [list trace add variable __:defer:__ unset $trace]
  return [list trace remove variable __:defer:__ unset $trace]
}
