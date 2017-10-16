if 0 {
  @ bpacket type | flags
    A list of booleans prefixed by length.
}
variable ::bpacket::type::current flags

bpacket register $::bpacket::type::current 8

if {[info command ::bpacket::type::$::bpacket::type::current] eq {}} {
  ::oo::class create ::bpacket::type::$::bpacket::type::current {}
}

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @init::$::bpacket::type::current {} {
    my requires varint boolean
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @encode::$::bpacket::type::current {value field args} {
    set values [list]

    if {[dict exists $field args]} {
      # when args are defined, each flag has a key
      set keys [dict get $field args]
      foreach key $keys {
        if {[dict exists $value $key]} {
          lappend values [dict get $value $key]
        } else {
          # we keep going until a key is not present - the rest are ignored
          # this will likely throw an error in the future.
          break
        }
      }
    } else {
      # when no args are provided, each value should be a boolean
      set values $value
    }

    append encoded [my @encode::varint [llength $values]]

    foreach flag $values {
      append encoded [my @encode::boolean $flag]
    }

    return $encoded
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @decode::$::bpacket::type::current {field args} {
    set length [my @decode::varint]

    if {[dict exists $field args]} {
      set keys   [dict get $field args]
      set decoded [dict create]
    } else {
      set decoded [list]
    }

    while {$length > 0} {
      set flag [my @decode::boolean]
      if {[info exists keys]} {
        set keys [lassign $keys key]
        dict set decoded $key $flag
      } else {
        lappend decoded $flag
      }
      incr length -1
    }

    return $decoded
  }
