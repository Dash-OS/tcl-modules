if 0 {
  @ bpacket type | boolean
    Encoded identically to a list (17) but expects that
    its keys will be rebuilt on the other side
}
variable ::bpacket::type::current boolean

bpacket register $::bpacket::type::current 3

if {[info command ::bpacket::type::$::bpacket::type::current] eq {}} {
  ::oo::class create ::bpacket::type::$::bpacket::type::current {
    variable DECODE_BUFFER
  }
}

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @encode::$::bpacket::type::current {value field args} {
    if {[string is boolean -strict $value]} {
      return [binary format c [expr {bool($value)}]]
    } else {
      tailcall return \
        -code error \
        -errorCode [list BINARY_PACKET ENCODE BOOLEAN VALUE_NOT_BOOLEAN] \
        " bpacket tried to encode a boolean but the value it received (${value}) is not a boolean."
    }
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @decode::$::bpacket::type::current args {
    binary scan $DECODE_BUFFER ca* bool DECODE_BUFFER
    return $bool
  }
