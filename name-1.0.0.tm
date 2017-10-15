if 0 {
  @ name @
    | A shortcut for reporting the name of the proc
    | or method from which it is called.
  @arg format -opts {$name|$method|$proc|$class|$args}
    Allows setting the format of the returned value.
    By default, name will simply return its own name,
    being either the method or proc name.
  @arg fail {string}
    If we fail to capture the given name or format, returns
    this value (also if subst provides an error).
  @returns {string}
    Return the substituted string based on the given
    format.  A [subst] call is performed expecting that
    the only variables present will be the ones provided
    above.
}
proc name {{format {$name}} {fail ?unknown?}} {
  set f1 [info frame [expr { [info level] - 0 }]]
  set f2 [info frame [expr { [info level] - 1 }]]
  if {[dict exists $f1 class]} {
    set class  [dict get $f1 class]
    set args [lassign [dict get $f2 cmd] object]
    set method [dict get $f1 method]
    set name $method
  } elseif {[dict exists $f1 proc]} {
    set args [lassign [dict get $f2 cmd] name]
    set proc $name
  } else {
    return $fail
  }
  if {[catch {subst $format} response]} {
    return $fail
  } else {
    return $response
  }
}
