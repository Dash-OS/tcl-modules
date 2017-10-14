if 0 {
  @ bpacket type | list
    A list of varints prefixed by the list length.
}
variable ::bpacket::type::current list

bpacket register $::bpacket::type::current 4

if {[info command ::bpacket::type::$::bpacket::type::current] eq {}} {
  ::oo::class create ::bpacket::type::$::bpacket::type::current {}
}

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @init::$::bpacket::type::current {} {
    # depends upon varint and string
    my requires varint string
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @encode::$::bpacket::type::current {value field args} {
    append response [my @encode::varint [llength $value]]
    foreach element $value {
      append response [my @encode::string $element]
    }
    return $response
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @decode::$::bpacket::type::current args {
    set length   [my @decode::varint]
    set response [list]
    while {$length > 0} {
      lappend response [my @decode::string]
      incr length -1
    }
    return $response
  }
