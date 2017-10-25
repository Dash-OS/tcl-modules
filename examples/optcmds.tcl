package require optcmds

# import omethod, oproc, oapply
namespace import ::optcmds::*

# simple example
oproc myproc {-foo -- bar} {
  if {[info exists opts(-foo)]} {
    return $bar
  } else {
    return 0
  }
}

proc benchmyproc {} {
  time {myproc -foo one} 10000
}

myproc -foo one
# one

myproc two
# 0

# default values are possible on any named values (not on switched values)
oproc defaultsproc {
  -command {callback ::cleanup}
  -timeout {ms 15000}
  -keepalive
  --
} {
  parray opts
}

# $opts() contains the raw options that were received in a way that can then
# be passed easily
defaultsproc
# opts()         = -command ::cleanup -timeout 15000
# opts(-command) = ::cleanup
# opts(-timeout) = 15000

defaultsproc -command mycallback -keepalive
# opts()           = -command mycallback -timeout 15000 -keepalive
# opts(-command)   = mycallback
# opts(-keepalive) = 1
# opts(-timeout)   = 15000

# it may be preferrable to instead receive a [dict] instead of [array] for
# the opts value.  this can be achieved with -optsdict at this time this is
# largely to provide various implementations to helpl determine the
# best / generally accepted way for the final specification:
oproc -dictopts defaultsproc {
  -command {callback ::cleanup}
  -timeout {ms 15000}
  -keepalive
  --
} {
  puts $opts
}

defaultsproc -command mycallback -keepalive
# -command mycallback
# -timeout 15000
# -keepalive 1
# {} {-command mycallback -timeout 15000 -keepalive}

# the name of the opts variable can be changed if needed - this is another
# thing that likely wouldnt be apart of a final specification
oproc -opts optsArray defaultsproc {
  -command {callback ::cleanup}
  -timeout {ms 15000}
  -keepalive
  --
} {
  parray optsArray
}
defaultsproc -command mycallback -keepalive
# optsArray()           = -command mycallback -timeout 15000 -keepalive
# optsArray(-command)   = mycallback
# optsArray(-keepalive) = 1
# optsArray(-timeout)   = 15000

# if one would rather simply have all the values as local variables, it can be
# done with -noopts or by providing -opts {} .
oproc -localopts defaultsproc {
  -command {callback ::cleanup}
  -timeout {ms 15000}
  -keepalive
  --
} {
  puts [info locals]
}
defaultsproc -command mycallback -keepalive
# -timeout -command -keepalive

namespace eval ::test {
  # create ::test::lambda with an option to set the namespace to use for
  # the apply invocation. If not defined, default to current namespace instead
  # of global (::test)
  oproc lambda {-ns namespace -- args} {
    if {[info exists opts(-ns)]} {
      set ns $opts(-ns)
    } else { set ns [namespace current] }
    # using options-based apply:
    oapply [list {-foo -- args} {
      parray opts
      puts "Namespace: [namespace current]"
      puts "args | $args"
    } $ns] {*}$args
  }
}

# note that this still works even if invoked like:
# ::test::lambda -ns :: -foo one two three
#
# where -ns is an option to the oproc and -foo is an option
# to the oapply.
#
# obviously the safest option is to instead invoke like:
#
# ::test::lambda -ns :: -- -foo one two three
# -or-
# ::test::lambda -ns :: -- -foo -- one two three
#
# since we are passing the arguments of two different option invocations.
::test::lambda -ns {} -foo one two three
# opts()     = -foo
# opts(-foo) = 1
# Namespace: ::
# args | one two three
::test::lambda -foo one two three
# opts()     = -foo
# opts(-foo) = 1
# Namespace: ::test
# args | one two three


##### TclOO

::oo::class create myclass {
  omethod test {-foo -- args} {
    puts "omethod called!"
    parray opts
    puts $args
  }
}

myclass create ::test::myobj
::test::myobj test -foo one two three
# omethod called!
# opts()     = -foo
# opts(-foo) = 1
# one two three

# since omethod is itself an optcommand, we can pass -define to request
# it simply returns the value it normally executes in our scope.  This
# allows us to pass it to ::oo::define for example:
::oo::define myclass {*}[omethod -define test {-foo -bar barVal -- args} {
  puts "modified omethod called!"
  parray opts
  puts $args
}]

::test::myobj test -foo -bar FTW! one two three
# modified omethod called!
# opts()     = -foo -bar FTW!
# opts(-bar) = FTW!
# opts(-foo) = 1
# one two three

####### apply

# sometimes we want apply to provide a command which can later be executed
# instead of executing it right away.  we can either call it into a list
# or use -define
variable example_lambda {{-foo -bar -- args} {
  parray opts
  if {[info exists opts(-foo)]} {
    return foo!
  } elseif {[info exists opts(-bar)]} {
    return bar!
  } else {
    return boring!
  }
}}

# showing with and without -- being used here.  the trailing --
# could be considered important as it guarantees in this case that
# no more options will be passed to the lambda once we create it,
# otherwise one could do {*}$foo -bar causing both -foo and -bar to
# be provided.
set foo [oapply -define $example_lambda -foo --]

# or could just do something like this - noting that the former
# is pre-processing the lambda so will be significatly faster (about 15-20x faster)
set bar [list oapply -- $example_lambda -bar --]

set fooval [{*}$foo 1 2 3]
# opts()     = -foo
# opts(-foo) = 1
# foo!
puts "$fooval is foo!"

set barval [{*}$bar 4 5 6]
# opts()     = -bar
# opts(-bar) = 1
# bar!
puts "$barval is bar!"

proc benchfoo {} {
  time {{*}$::foo 1 2 3} 10000
}
proc benchbar {} {
  time {{*}$::bar 4 5 6} 10000
}


# per the wiki article, a change was made for switch-style
# opts to increment their values when provided more than
# one time.
oproc myproc {-v -- args} {
  if {[info exists opts(-v)]} {
    puts "verbosity level is $opts(-v)"
  }
}

myproc -v -v -v hello!


# awesome, the body only has an incr... but the args take time to read and
# understand
proc namedproc { {var -name var -upvar 1 -required 1} {i -name i -default 1} } {
  incr var $i
}

proc optsproc {-var varName -i {incr 1} --} {
  if {![info exists opts(-var)]} {
    # throw your error here - with any implementation-specific information
    # helpful to the caller
  } else {
    upvar $opts(-var) var
    incr var $opts(-i)
  }
}
