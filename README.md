# Tcl Micro Modules & Packages

Included is a list of some of the modules that we use often within our various 
Tcl Scripts & Applications.  Many of them are extremely small and simple (1-3 lines).  

While many were created by us, some of them were taken or adapted from our various 
encounters in the [Tcl Wiki](http://wiki.tcl.tk/), other open source communities, or the excellent Tcl IRC Chatroom. 
We have tried to add credits or links to reference and provide credit whenever possible. 
If anyone was left out and you see some of your code just let us know and I will get it 
added as quickly as possible!

One of Tcl's best features is how flexible the language itself is.  Many of these modules 
take advantage of that fact to provide new features and options while writing your 
applications.

Feel free to use any of these however you wish. 

##### **If you have any good ones that should be added - send them over!**

Would love to collect any other "awesome" and useful Tcl procs that you find yourself 
using and others may find useful.  

## Package Summaries

I will try to provide a basic idea of some of the modules as time goes on.

### Table Of Contents 

 - [callback](#callback-command-args)
 - [cmdlist](#cmdlist-args)
 - [valias](#valias-source-alias)
 - [extend](#extend-namespace-body)
 - [run](#run-scoped-vars-level-script)
 - [time parse](#time-parse-args)
 - [pubsub](#pubsub-command-args)
 - [ensembled](#ensembled)


---

### `callback` *command ?...args?*

A favorite among many tclers, a simple way to setup a callback command that will resolve 
to the current namespace.  This is especially useful when scheduling callbacks 
from within TclOO Objects.

<details><summary><b>Simple Example</b></summary><p>

```tcl
package require callback

namespace eval foo {
  proc start args {
    after 0 [callback complete {*}$args]
  }
  
  proc complete args {
    puts "Complete! $args"
  }
}

foo::start one two three
```

</p></details>

<details>
<summary>
<b>TclOO Example</b>
</summary>
<p>

```tcl
package require callback

::oo::class create MyClass {
  method start args {
    after 0 [callback my Complete {*}$args]
  }
  
  # Works even with unexpored methods!
  method Complete args {
    puts "Complete! $args"
  }
}

set obj [MyClass new]
$obj start one two three
```

</p>
</details>

---

### `cmdlist` *?...args?*

An extremely simple but useful procedure that helps when you have to construct commands 
that may need to be evaluated both in the current context as well as in another (such 
as when calling uplevel or doing a coroutine injection).  

<details>
<summary>
<b>Simple Example</b>
</summary>
<p>

While a silly example, it is the simplest example of how this might be useful I could 
think of.  In general when we use this it is for building control structures and/or 
for coroutine injection.

```tcl
package require cmdlist

proc foo { name value } {
  set one   foo
  set two   bar
  set three baz
  modify $name $value
}

proc modify { varname value } {
  uplevel 1 [cmdlist \
    {report $one $two $three} \
    [list set $varname $value] \
    {report $one $two $three}
  ]
}

proc report { args } {
  puts "Value: $args"
}

foo two newvalue

# Value: foo bar baz
# Value: foo newvalue baz
```

</p>
</details>

---

### `valias` *source* *alias*

Another extremely simple one, valias is used to alias a variable to another 
variable so that their values will always match.  Modifying one will be reflected 
in the other.  

<details>
<summary>
<b>Simple Example</b>
</summary>
<p>

```tcl
package require valias

set foo "Hello"

valias foo bar 

puts $bar
# "Hello"

set bar "Hello, World!"

puts $foo
# "Hello, World!"
puts $bar
# "Hello, World!"

```

</p>
</details>

---

### `extend` *namespace* *body*

Taking advantage of Tcl's [namespace ensemble](https://www.tcl.tk/man/tcl8.6/TclCmd/namespace.htm#M30) features, 
extend allows us to "extend" the core Tcl Ensembles with new functionality.  

 - **See Also:** [Tcl Wiki Page](http://wiki.tcl.tk/15566)
 
<details>
<summary>
<b>[string cat] polyfill</b>
</summary>
<p>

Here is an example of extending string to add 8.6's [string cat] feature in situations 
that our script may be running in earlier versions.

```tcl
package require extend

extend string {
  if { [::catch {::string cat}] } {
    proc cat args { ::join $args {} }
  }
}

puts [string cat one two]
# onetwo
```

</p>
</details>

---

### `time parse` ?...args?

`[time parse]` is a convenience package 

---

### `run ?-scoped? ?-vars [list]? ?-level #? -- script` 

`[run]` provides a flexible utility for running a given script within an (optionally)
scoped environment.  It is run within "apply" so the return value of the script is the 
value `[run]` will return.

<details>
<summary>
<b>Simple Example</b>
</summary>
<p>

```tcl
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
  
  set response [ run -level 2 -vars myvar -upvar {
    # 2 levels up lets change the value of myvar
    set myvar changed
  } ]
  
  puts "::foo::next_proc | response $response"
  
}

set myvar my_value
puts ":: | myvar $myvar"
puts "--- Call ::foo::start ---"
::foo::start $myvar
puts "--- After ::foo::start ---"
puts ":: | myvar $myvar"
```

</p>
</details>

---

### `pubsub command ?args?`

`[pubsub]` aims to provide an extremely simple publisher/subscriber pattern for 
handling the execution of one or more commands when a given message/path is 
published to.

#### Subscribing to a Path

**`pubsub subscribe id ?...path? callback`**

```tcl
pubsub subscribe MySubscription MY_EVENT my_proc
# Multiple
pubsub subscribe MySubscription2 MY_EVENT my_proc
pubsub subscribe MySubscription3 MY_EVENT my_proc
# Nested Paths
pubsub subscribe B1Press   button_one pressed  my_proc
pubsub subscribe B1Release button_one release  my_proc
```

#### Publishing to a Path

**`pubsub dispatch data ?...path?`**

```tcl
# Returns the total # of subscribers that were executed as a 
# result of the dispatch.
set total_executed [ pubsub dispatch [dict create foo bar] MY_EVENT ]

if { ! [ pubsub dispatch [dict create foo bar] button_one pressed ] } {
  puts "No Subscribers"
}
```

#### Unsubscribing by ID or Path

**`pubsub unsubscribe id`**
**`pubsub unsubscribe_path ?...path?`**

```tcl
pubsub unsubscribe MySubscription
pubsub unsubscribe_path MY_EVENT
```

#### Triggering a Subscription by ID

**`pubsub trigger id`**

```tcl
pubsub trigger MySubscription
```

#### Resetting / Removing all Subscriptions

**`pubsub reset`**

```tcl
pubsub reset
```

---


### `ensembled`

`[ensembled]` is really just a nice little convenience wrapper for defining 
a namespace which will act as an ensemble and will export all procedures that 
start with a lower-case [a-z] character.

<details>
<summary>
<b>Simple Example</b>
</summary>
<p>

```tcl

package require ensembled

namespace eval foo ensembled

proc foo::call args { puts $args }

foo call one two three

# one two three
```

</p>
</details>

---
