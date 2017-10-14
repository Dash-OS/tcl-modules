if 0 {
  @ bpacket type | flags
    A list of varints prefixed by the list length.
}
variable ::bpacket::type::current numlist

bpacket register $::bpacket::type::current 7

if {[info command ::bpacket::type::$::bpacket::type::current] eq {}} {
  ::oo::class create ::bpacket::type::$::bpacket::type::current {}
}

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @init::$::bpacket::type::current {} {
    my requires varint
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @encode::$::bpacket::type::current {value field args} {
    append response [my @encode::varint [llength $value]]
    foreach num $value {
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
    set flags  [list]
    while {$length > 0} {
      lappend flags [my @decode::varint]
      incr length -1
    }
    return $flags
  }
