if 0 {
  @ bpacket type | varint
    provides bpacket with the capability of
    encoding & decoding varint values
}
variable ::bpacket::type::current varint

bpacket register $::bpacket::type::current 0

if {[info command ::bpacket::type::$::bpacket::type::current] eq {}} {
  ::oo::class create ::bpacket::type::$::bpacket::type::current {
    variable DECODE_BUFFER
  }
}

::oo::define ::bpacket::type::$::bpacket::type::current {
  variable DECODE_BUFFER
}

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @encode::$::bpacket::type::current {value {field {}} args} {
    return [bpacket encode varint $value]
  }

::oo::define ::bpacket::type::$::bpacket::type::current \
  method @decode::$::bpacket::type::current args {
    lassign [bpacket decode varint $DECODE_BUFFER] varint DECODE_BUFFER
    return $varint
  }

# provides a utility to read varint values outside of the
# reader context - returning a list of elements
# $varint $cursor $remaining
proc ::bpacket::decode::varint data {
  # remove our wrapper value before parsing any varint
  # our cursor indicates the location where the data
  # begins and the varint completes, including the removal
  # of any WRAPPER values.
  # set cursor 0
  # set wrapper_length [string length $::bpacket::HEADER]
  while {[string match ${::bpacket::HEADER}* $data]} {
    # we need to count how many times we shift so we can
    # return the index for the start of the data from our
    # current position
    incr cursor $wrapper_length
    set data [string range $data ${wrapper_length} end]
  }
  set shift -7
  set x 0
  set i 128
  while { $i & 128 } {
    binary scan $data ca* i data
    set x [expr { ( (127 & $i ) << [incr shift 7] ) | $x }]
    incr cursor
  }
  return [list $x $data $cursor]
}

proc ::bpacket::encode::varint value {
  if {$value < 128} {  ; # 2**7
    return [binary format c $value]
  } elseif {$value < 16384} {  ; # 2**14
    append x \
      [binary format c [expr {($value & 127) | 128}]] \
      [binary format c [expr {$value >> 7}]]
    return $x
  } elseif {$value < 2097152} {  ;# 2**21
    append x \
      [binary format c [expr {($value & 127) | 128}]] \
      [binary format c [expr {(($value >> 7) & 127) | 128}]] \
      [binary format c [expr {$value >> 14}]]
    return $x
  } else {
    set sh 0
    while {1} {
      set b [expr {($value >> $sh) & 127}]
      incr sh 7
      if {$value >> $sh} {
        append x [binary format c [expr {$b | 128}]]
      } else {
        return $x[binary format c $b]
      }
    }
  }
  return $x
}
