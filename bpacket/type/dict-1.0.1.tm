if 0 {
  @ bpacket type | dict
    Encoded identically to a list (4) but expects that
    its keys will be rebuilt on the other side.  Each key
    given in args is lappened to the list in the given order
    then re-assembled on the other end based upon that order.

    Any keys not defined are not transmitted.

    If the dict does not have a given key it is an error.
}
variable ::bpacket::type::current dict

bpacket register $::bpacket::type::current 7

if {[info command ::bpacket::type::$::bpacket::type::current] eq {}} {
  ::oo::class create ::bpacket::type::$::bpacket::type::current {}
}

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @init::$::bpacket::type::current {} {
    my requires list
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @encode::$::bpacket::type::current {value field args} {
    set keys   [dict get $field args]
    set values [list]
    foreach key $keys {
      if {[dict exists $value $key]} {
        lappend values [dict get $value $key]
      } else {
        tailcall return \
          -code error \
          -errorCode [list BINARY_PACKET ENCODE FIELD DICT MISSING_KEY $key] \
          " bpacket tried to encode a dict (field [dict get $field name]) but the required key \"$key\" was not present"
      }
    }
    if {[llength $values]} {
      return [my @encode::list $values $field]
    }
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @decode::$::bpacket::type::current args {
    set args [lassign $args field]
    if {![dict exists $field args]} {
      tailcall return \
        -code error \
        -errorCode [list BINARY_PACKET DECODE FIELD DICT FIELD_REQUIRED] \
        " decoding dict requires the field value"
    }
    set response [dict create]
    set keys     [dict get $field args]
    set values   [my @decode::list]
    foreach key $keys {
      set values [lassign $values value]
      dict set response $key $value
    }
    return $response
  }
