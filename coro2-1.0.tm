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
proc ::coro::yields args { tailcall yield $args }

# Runs a simple check to see if the coroutine exists or not.  
proc ::coro::exists { coro } { tailcall expr [format { [info commands {%s}] ne {} } $coro] }

# Attempts to determine if the given coroutine is the coroutine we are currently in.  
# This should generally not be needed and we should know this but it can be useful
# in certain situations.
proc ::coro::running { coro } { string match *$coro [info coroutine] }