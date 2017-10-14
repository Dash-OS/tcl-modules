if 0 {
  @ bpacket type | flags
    A list of booleans prefixed by length.
}
variable ::bpacket::type::current flags

bpacket register $::bpacket::type::current 6

if {[info command ::bpacket::type::$::bpacket::type::current] eq {}} {
  ::oo::class create ::bpacket::type::$::bpacket::type::current {}
}

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @init::$::bpacket::type::current {} {
    my requires varint boolean
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @encode::$::bpacket::type::current {value field args} {
    append response [my @encode::varint [llength $value]]
    foreach flag $value {
      append response [my @encode::boolean $flag]
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
