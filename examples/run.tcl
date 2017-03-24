package require run

namespace eval foo {}

proc ::foo::start { myvar } {
  set i 0
  puts "::foo::start | myvar $myvar"
  puts "::foo::start | i     $i"
  puts "--- Call next_proc ---"
  next_proc i 
  puts "--- After next_proc ---"
  puts "::foo::start | myvar $myvar"
  puts "::foo::start | i     $i"
}

proc ::foo::next_proc args {
  set foo bar
  
  # we can run scoped commands locally
  puts "::foo::next_proc | foo $foo"
  run -scoped {
    # oh no!
    set foo my_value
    puts "::foo::next_proc run -scoped | unsetting all known vars: [info vars]"
    foreach var [info vars] { 
      puts "::foo::next_proc run -scoped | unset $var with value [set $var]"
      unset $var 
    } ; unset var
    puts "::foo::next_proc run -scoped | vars known: [info vars]"
  }
  
  # lets run a command, scoped, in the level above us with myvar and duration.
  # we may optionally specify -upvar to have the vars attached to the scope.
  run -scoped -vars $args -level 1 -upvar {
    # we are running a scoped script in the level above us.  We have brought in 
    # the variables specified by $args (i) which is the only variable which we
    # are modifying in this case.
    incr i
    # we don't have to worry about collisions with the scope
    set myvar collision_occurred
    set foo   qux
    puts "::foo::next_proc run -scoped -upvar | myvar $myvar | i $i | foo $foo"
  }
  
  puts "::foo::next_proc | known vars | [info vars] | foo $foo"
  
  run -level 2 -vars myvar -upvar {
    # 2 levels up lets change the value of myvar
    set myvar changed
  }
  
  
  
}

set myvar my_value
puts ":: | myvar $myvar"
puts "--- Call ::foo::start ---"
::foo::start $myvar
puts "--- After ::foo::start ---"
puts ":: | myvar $myvar"