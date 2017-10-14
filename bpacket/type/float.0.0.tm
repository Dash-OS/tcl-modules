if 0 {
  @ bpacket type | float
    handles float values.

    1. its first bit indicates whether the value is 32-bit or 64-bit
    2. it expects that the machine uses  IEEE floating point representations.
    3. if any machine that may need to decode uses other formatting - use string or varint.
}
variable ::bpacket::type::current float

bpacket register $::bpacket::type::current 4

if {[info command ::bpacket::type::$::bpacket::type::current] eq {}} {
  ::oo::class create ::bpacket::type::$::bpacket::type::current {}
}

::oo::define ::bpacket::type::$::bpacket::type::current {
  variable DECODE_BUFFER
}

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @encode::$::bpacket::type::current {value args} {
    set result {}
    if {$value > 2147483647 || $value < -2147483647} {
      append result \
        [binary format c 1] \
        [binary format q $value]
    } else {
      append result \
        [binary format c 0] \
        [binary format r $value]
    }
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @decode::$::bpacket::type::current {args} {
    set length [my @decode::varint]
    binary scan $DECODE_BUFFER a${length}a* data DECODE_BUFFER
    return $data
  }

proc ::bpacket::encode::float value {
  set result {}
  if {$value > 2147483647 || $value < -2147483647} {
    append result \
      [binary format c 1] \
      [binary format q $value]
  } else {
    append result \
      [binary format c 0] \
      [binary format r $value]
  }
  return $result
}

proc ::bpacket::decode::float value {
  binary scan $value c1a* type value
  if {$type == 0} {
    binary scan $value r1a* value remaining
  } else {
    binary scan $value q1a* value remaining
  }
  return $value
}
