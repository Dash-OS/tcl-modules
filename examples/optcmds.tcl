package require optcmds

# import omethod, oproc, oapply
namespace import ::optcmds::*

# simple example
oproc myproc {-foo -- bar} {
  puts "opts | $opts"
  puts "bar  | $bar"
}

myproc -foo one
# opts | -foo 1
# bar  | one

myproc two
# opts |
# bar  | two

namespace eval ::test {
  # create ::test::lambda with an option to set the namespace to use for
  # the apply invocation. If not defined, default to current namespace instead
  # of global (::test)
  oproc lambda {-ns namespace -- args} {
    if {[dict exist $opts -ns]} {
      set ns [dict get $opts -ns]
    } else { set ns [namespace current] }
    # using options-based apply:
    oapply [list {-foo -- args} {
      puts [namespace current]
      puts "opts | $opts"
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
#  ::
#  opts | -foo 1
#  args | one two three


##### TclOO

::oo::class create myclass {
  omethod test {-foo -- args} {
    puts "omethod called!"
    puts "$opts"
    puts $args
  }
}

myclass create ::test::myobj
::test::myobj test -foo one two three
# omethod called!
# -foo 1
# one two three

# since omethod is itself an optcommand, we can pass -define to request
# it simply returns the value it normally executes in our scope.  This
# allows us to pass it to ::oo::define for example:
::oo::define myclass {*}[omethod -define test {-foo -bar barVal -- args} {
  puts "modified omethod called!"
  puts "$opts"
  puts $args
}]

::test::myobj test -foo -bar FTW! one two three
# modified omethod called!
# -foo 1 -bar FTW!
# one two three

####### apply

# sometimes we want apply to provide a command which can later be executed
# instead of executing it right away.  we can either call it into a list
# or use -define
variable example_lambda {{-foo -bar -- args} {
  puts "opts! | $opts"
  puts "args! | $args"
  if {[dict exists $opts -foo]} {
    return foo!
  } elseif {[dict exists $opts -bar]} {
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
# is pre-processing the lambda so will be significatly faster
set bar [list oapply -- $example_lambda -bar --]

set fooval [{*}$foo 1 2 3]
# opts! | -foo 1
# args! | 1 2 3
# $fooval = foo!
puts "$fooval is foo!"

set barval [{*}$bar 4 5 6]
# opts! | -bar 1
# args! | 4 5 6
# $barval = bar!
puts "$barval is bar!"
