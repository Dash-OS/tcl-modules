# TclOO Modules

Since these are a little bit more involved, we will add the information below for 
them.

### `::oo::metaclass`

```tcl
::oo::metaclass create Module {
  method static {prop {data {}}} {
    my variable $prop
    if { [info exists $prop] && $data eq {} } {
       return [set $prop]
    } else { set $prop $data }
  }
  method meta { {meta {}} } {
    my variable @meta
    if { ! [info exists @meta] } { set @meta {} }
    if { $meta ne {} && [set $meta] eq {} { set @meta [string trim $meta] }
    return [set @meta]
  }
}

Module create ModuleOne {
  # static meta value we can access from any method
  # using [meta].  It is saved to the classes namespace.
  meta {
    title "My Module"
  }
  constructor {} {
    set modules [static modules] 
    lappend modules [self]
    static modules $modules
    puts "Modules: $modules"
    puts "Meta is: [meta]"
  }
}

ModuleOne new 
ModuleOne new 
ModuleOne new

# Modules: ::Obj2
# Meta is: title "My Module"
# Modules: ::Obj2 ::Obj3
# Meta is: title "My Module"
# Modules: ::Obj2 ::Obj3 ::Obj4
# Meta is: title "My Module"

```