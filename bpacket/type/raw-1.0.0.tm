if 0 {
  @ bpacket type | raw
    provides bpacket with the capability of
    encoding & decoding raw bytes -
    these are not encoded to utf-8
}
variable ::bpacket::type::current raw

bpacket register $::bpacket::type::current 3

if {[info command ::bpacket::type::$::bpacket::type::current] eq {}} {
  ::oo::class create ::bpacket::type::$::bpacket::type::current {
    variable DECODE_BUFFER
  }
}

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @encode::$::bpacket::type::current {value field args} {
    append response \
      [my @encode::varint [string length $value]] \
      $value
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @decode::$::bpacket::type::current {field args} {
    set length [my @decode::varint]
    binary scan $DECODE_BUFFER a${length}a* data DECODE_BUFFER
    return $data
  }
