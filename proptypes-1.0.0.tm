if 0 {
  @ proptypes @
    | Validate property types of a dict in an efficient manner
    | while taking care to provide clear stack traces when
    | errors do occur.

    > Disabling proptypes checking
      Checking proptypes can become an intensive task.  By defining
      the TCL_ENV environment variable, proptypes checking can be
      toggled on and off.

      If TCL_ENV is set and it is not "development" then the proptypes
      check will be an empty proc accepting any number of args.

      If TCL_ENV is set after the package is required, it will still
      be checked and we will immediately return whenever proptypes
      is called.

  @arg dict {dict<key, mixed>}
    The dict to compare against
  @arg args {[dict] | ...[dict]}
    Either a single element or multiple elements which make up a
    valid dict.  Each key should map to the desired type.

    @shape
      Some types allow for nested type checking.  These values accept either
      2 or 3 arguments where the second argument is the shape and the third
      is the optional boolean value defined in the {@optional} section.

      @shapes {shape|list|tuple}
        @shape {dict}
        {
          # expects [dict create foo [dict create bar $entierValue]]
          proptypes $mydict {
            foo {shape {
              bar entier
            }}
          }
        }
        @shape {list}
        {
          # expects a list of dicts that contains a key "foo" with an entier value.
          proptypes $myDict {
            foo {list {shape {foo entier}}}
          }
        }
        @shape {tuple}
        {
          # expects a tuple (an exact list) containing 3 elements of types any entier boolean
          proptypes $myDict {
            foo {tuple {any entier boolean}}
          }
        }

    @optional
      If a value should be optional, the value can be a list with its
      second value being a boolean indicating whether or not the value is
      required.

      Optional values will be type checked only if they exist in the dict.
  @example
  {
    proc typedProc args {
      proptypes $args {
        foo dict
        bar entier
        baz {boolean false}
        qux {shape {
          foo {tuple {string boolean entier}}
        } false}
      }
      puts "Validated!"
    }

    typedProc foo [dict create one two] bar 2
    # OK: Validated!
    typedProc foo [dict create one two] bar hi
    # ERROR: invalid type for prop bar, expected entier
    typedProc foo [dict create one two] baz true
    # ERROR: required value bar not found
    typedProc foo [dict create one two] bar 2 baz 2
    # ERROR: invalid type for prop baz, expected boolean
  }
}

if {[info exists ::env(TCL_ENV)]} {
  if {$::env(TCL_ENV) != "development"} {
    proc proptypes args {}
  }
}

if {![info exists ::env(TCL_ENV)] || [info command proptypes] eq {}} {
  proc proptypes {dict args} {
    if {[info exists ::env(TCL_ENV)] && $::env(TCL_ENV) != "development"} {
      # check in case the env var was defined later
      return
    }
    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }
    dict for {prop type} $args {
      set config [lassign $type type]
      if {$type in [list shape tuple list]} {
        lassign $config shape required
      } else {
        lassign $config required
      }
      if {$required eq {}} {
        set required true
      }
      if {[dict exists $dict $prop]} {
        set value [dict get $dict $prop]
        switch -- $type {
          any - string { break }
          number {
            if {![string is double -strict $value]} {
              tailcall return -code error -errorCode [list INVALID_PROP $prop] " invalid type for prop ${prop}, expected $type"
            }
          }
          dict {
            if {[catch {dict size $value} err]} {
              tailcall return -code error -errorCode [list INVALID_PROP $prop] " invalid type for prop ${prop}, expected dict but received value with [llength $value] elements"
            }
          }
          bool {
            if {![string is boolean -strict $value]} {
              tailcall return -code error -errorCode [list INVALID_PROP $prop] " invalid type for prop ${prop}, expected $type"
            }
          }
          tuple {
            # exact # of elements matching the given type
            # tuple {string entier boolean}
            if {[llength $shape] != [llength $value]} {
              tailcall return -code error -errorCode [list INVALID_PROP $prop WRONG_NUMBER_ELEMENTS] " invalid type for prop ${prop}, expected tuple with [llength $shape] elements but received a value with [llenght $value] elements"
            } else {
              upvar 1 level plevel
              if {![info exists plevel]} {
                set level 0
                set plevel 0
              } else {
                set level [expr {$plevel + 1}]
              }
              set e 0
              foreach tupleType $shape {
                set cname ${prop}.$e
                set cval   [dict create $cname [lindex $value $e]]
                set cshape [dict create $cname $tupleType]
                if {[catch {proptypes $cval $cshape} err]} {
                  if {$level == 1} {
                    tailcall return -code error -errorCode [list INVALID_PROP $cname INVALID_TUPLE] "invalid element (${e}) for tuple ${cname} \n[string repeat { } $level]$err"
                  } else {
                    return -code error -errorCode [list INVALID_PROP $cname INVALID_TUPLE] "invalid element (${e}) for tuple ${cname} \n[string repeat { } $level]$err"
                  }
                }
                incr e
              }
            }
          }
          list {
            # exact # of elements matching the given type
            # tuple {string entier boolean}
            if {[llength $value] == 0} {
              tailcall return -code error -errorCode [list INVALID_PROP $prop WRONG_NUMBER_ELEMENTS] " invalid type for prop ${prop}, expected list with at least one element of type $shape"
            } else {
              upvar 1 level plevel
              if {![info exists plevel]} {
                set level 0
                set plevel 0
              } else {
                set level [expr {$plevel + 1}]
              }
              set e 0
              foreach larg $value {
                set cname ${prop}.$e
                set cval   [dict create $cname [lindex $value $e]]
                set cshape [dict create $cname $shape]
                if {[catch {proptypes $cval $cshape} err]} {
                  if {$level == 1} {
                    tailcall return -code error -errorCode [list INVALID_PROP $cname INVALID_LIST] "invalid element (${e}) for list ${prop} \n[string repeat { } $level]$err"
                  } else {
                    return -code error -errorCode [list INVALID_PROP $cname INVALID_LIST] "invalid element (${e}) for list ${prop} \n[string repeat { } $level]$err"
                  }
                }
                incr e
              }
            }
          }
          shape {
            upvar 1 level plevel
            if {![info exists plevel]} {
              set level  1
              set plevel 0
            } else {
              set level [expr {$plevel + 1}]
            }
            if {[catch {proptypes $value $shape} err]} {
              if {$level == 1} {
                tailcall return -code error -errorCode [list INVALID_PROP $prop INVALID_SHAPE] "invalid shape for prop ${prop} \n[string repeat { } $level]$err"
              } else {
                return -code error -errorCode [list INVALID_PROP $prop INVALID_SHAPE] "invalid shape for prop ${prop} \n[string repeat { } $level]$err"
              }
            }
          }
          default {
            if {![string is $type -strict $value]} {
              tailcall return -code error -errorCode [list INVALID_PROP $prop] " invalid type for prop ${prop}, expected $type"
            }
          }
        }
      } elseif {$required} {
        tailcall return -code error -errorCode [list PROP_REQUIRED $prop] " required value $prop not found"
      }
    }
  }
}
