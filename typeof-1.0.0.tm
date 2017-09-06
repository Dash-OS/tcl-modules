if 0 {
  @ typeof @
    | Attempts to capture the "type" of the value by
    | checking the underlying tcl representation of the
    | value.
    > Important <
      | This can not be depended upon as values representations
      | may change at various points when code is evaluated.
  @value {any}
    The value that we want the type for.
  @args {?list<-opts>?}
    Optional opts to modify the execution of the
    function.
    @arg -exact
      Does not parse the value returned into simpler representations.
      For example, it wont check if "pure string" is actually a "number".
    @arg -deep
      Attempts to resolve the type in a deep manner.  This will follow
      dicts and lists, checking the type of their values.
}
proc typeof {value args} {
  regexp {^value is a (.*?) with a refcount} \
    [::tcl::unsupported::representation $value] -> type
  # parse the type to return simpler representations
  if {"-exact" ni $args} {
    switch -glob -- $type {
      boolean* {
        set type boolean
      }
      *string {
        # parse string to see if it is actually another value
        if {[string is entier -strict $value]} {
          set type number
        } elseif {[string is double -strict $value]} {
          set type number
        } elseif {[string is boolean -strict $value]} {
          set type boolean
        } else {
          set type string
        }
      }
      int - double {
        set type number
      }
    }
  }
  if {"-deep" in $args} {
    switch -- $type {
      list {
        set reps [list]
        foreach el $value {
          lappend reps [typeof $el {*}$args]
        }
        lappend type $reps
      }
      dict {
        set reps [dict create]
        dict for {k v} $value {
          dict set reps $k [typeof $v {*}$args]
        }
        lappend type $reps
      }
    }
  }
  return $type
}
