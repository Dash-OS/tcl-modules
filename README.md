# Tcl Micro Modules & Packages

Included is a list of some of the modules that we use often within our various 
Tcl Scripts & Applications.  Many of them are extremely small and simple (1-3 lines).  

While many were created by us, some of them were taken or adapted from our various 
encounters in the wiki, other open source communities, or the excellent Tcl IRC Chatroom. 
We have tried to add credits or links to reference and provide credit whenever possible. 
If anyone was left out and you see some of your code just let us know and I will get it 
added as quickly as possible!

One of Tcl's best features is how flexible the language itself is.  Many of these modules 
take advantage of that fact to provide new features and options while writing your 
applications.

Feel free to use any of these however you wish. 

##### **If you have any good ones that should be added - send them over!**

## Package Summaries

I will try to provide a basic idea of some of the modules as time goes on.

### Table Of Contents 

 - [callback](#callback-command-args)
 - [cmdlist](#cmdlist-args)
 - [valias](#valias-source-alias)
 
---

### `callback` *command ?...args?*

A favorite among many tclers, a simple way to setup a command that will resolve 
to the current namespace.  This is especially useful when scheduling callbacks 
from within TclOO Objects.


<details><summary>**Simple Example**</summary><p>

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



<details><summary>**TclOO Example**</summary><p>

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

</p></details>

---

### `cmdlist` *?...args?*

An extremely simple but useful package that helps when you have to construct commands 
that may need to be evaluated both in the current context as well as in another (such 
as when calling uplevel or doing a coroutine injection).  

<details>
<summary>
**Simple Example**
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
**Simple Example**
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
