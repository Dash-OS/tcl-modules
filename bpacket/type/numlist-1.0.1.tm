if 0 {
  @ bpacket type | flags
    A list of varints prefixed by the list length.
}
variable ::bpacket::type::current numlist

bpacket register $::bpacket::type::current 9

if {[info command ::bpacket::type::$::bpacket::type::current] eq {}} {
  ::oo::class create ::bpacket::type::$::bpacket::type::current {}
}

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @init::$::bpacket::type::current {} {
    my requires varint
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @encode::$::bpacket::type::current {value field args} {
    set values [list]

    if {[dict exists $field args]} {
      set keys [dict get $field args]
      foreach key $keys {
        if {[dict exists $value $key]} {
          lappend values [dict get $value $key]
        } else {
          # we keep going until a key is not present - the rest are ignored
          break
        }
      }
    } else {
      set values $value
    }

    append response [my @encode::varint [llength $values]]

    foreach num $values {
      if {![string is entier -strict $num]} {
        tailcall return \
          -code error \
          -errorCode [list BINARY_PACKET ENCODE NUM_LIST NOT_A_NUMBER $num] \
          " bpacket expected an entier value but got $num for field $field"
      }
      append response [my @encode::varint $num]
    }

    return $response
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @decode::$::bpacket::type::current {field args} {
    set length [my @decode::varint]

    if {[dict exists $field args]} {
      set keys   [dict get $field args]
      set result [dict create]
    } else {
      set result [list]
    }

    while {$length > 0} {
      set num [my @decode::varint]
      if {[info exists keys]} {
        set keys [lassign $keys key]
        dict set result $key $num
      } else {
        lappend result $num
      }
      incr length -1
    }

    return $result
  }
