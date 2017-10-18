package require decorator

namespace eval ::decorator::coro {}

if 0 {
  UNFINISHED
  @ coro decorator
    Define a proc or method which will create a coroutine
    when called.

  @example
  {
    @coro proc mycoro {one two} {
      puts [info coroutine]
      yield $one
      yield $two
    }

    set r [mycoro foo bar]
    $r ; # foo
    $r ; # bar
  }
}
decorator define @coro { definition command args } \
  -compile {
    switch -- $command {
      method - proc {
        
      }
    }
  }
