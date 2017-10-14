if 0 {
  @ bpacket type | string
    provides bpacket with the capability of
    encoding & decoding varint values
}
variable ::bpacket::type::current string

bpacket register $::bpacket::type::current 1

if {[info command ::bpacket::type::$::bpacket::type::current] eq {}} {
  ::oo::class create ::bpacket::type::$::bpacket::type::current {}
}

::oo::define ::bpacket::type::$::bpacket::type::current {
  variable DECODE_BUFFER
}

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @encode::$::bpacket::type::current {value args} {
    set value [encoding convertto utf-8 $value]
    append response \
      [my @encode::varint [string length $value]] \
      $value
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @decode::$::bpacket::type::current {args} {
    set length [my @decode::varint]
    binary scan $DECODE_BUFFER a${length}a* data DECODE_BUFFER
    return $data
  }
