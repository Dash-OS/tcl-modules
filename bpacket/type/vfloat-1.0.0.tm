if 0 {
  @ bpacket type | vfloat
    varint float - a (very) experimental float handling which attempts to
    pack the value by splitting it into two varints which are to be read
    consecutively.

    this likely is not handling more complex situations with numbers as it
    expects the number will be formatted in a [split] friendly way.

    this will likely make storing smaller floats like percents much more
    efficient (at least double)
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
    set s [split $value .]
    append result \
      [@encode::varint [lindex $s 0]] \
      [@encode::varint [lindex $s 1]]
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @decode::$::bpacket::type::current {args} {
    set length [my @decode::varint]
    binary scan $DECODE_BUFFER a${length}a* data DECODE_BUFFER
    return $data
  }

proc ::bpacket::encode::vfloat value {
  if {$value < 0} {
    append result [binary format c 0]
  } else {
    append result [binary format c 1]
  }
  set value [expr {abs($value)}]
  set s [split $value .]
  if {[llength $s] == 1} {
    lappend s 0
  }
  append result \
    [varint [lindex $s 0]] \
    [varint [lindex $s 1]]
}

proc ::bpacket::decode::vfloat value {
  binary scan $value ca* sign value
  if {$sign == 0} {
    set sign "-"
  } elseif {$sign == 1} {
    set sign {}
  } else {
    throw error "dont know sign $sign"
  }
  lassign [varint $value] one value
  lassign [varint $value] two remaining
  append result $sign $one . $two
  return [expr {double($result)}]
}
