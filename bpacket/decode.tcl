
::oo::class create ::bpacket::reader {}

::oo::define ::bpacket::reader {
  variable PACKET BUFFER
}

::oo::define ::bpacket::reader constructor packet {
  my set $packet
}

::oo::define ::bpacket::reader method reset {} {
  set BUFFER $PACKET
}

::oo::define ::bpacket::reader method set { packet } {
  set PACKET $packet
  set BUFFER $packet
}

::oo::define ::bpacket::reader method field {} {
  binary scan $BUFFER ca* i BUFFER
  set field [expr {($i & 120) >> 3}] ; set wire [expr {$i & 7}]
  #puts "Field: $field Wire $wire"
  if {!($i & 128)} { return [list $field $wire] }

  # == == == == == == == == == == == == == == == == == == == == == == == == =
  # 'int32':  shift = 4 11 18; # avoid negativ numbers i.e. bit 32.
  binary scan $BUFFER ca* i BUFFER ; set field [expr {((127 & $i) << 4) | $field}]
  if {!($i & 128)} { return [list $field $wire] }

  binary scan $BUFFER ca* i BUFFER ; set field [expr {((127 & $i) << 11) | $field}]
  if {!($i & 128)} { return [list $field $wire] }

  binary scan $BUFFER ca* i BUFFER ; set field [expr {((127 & $i) << 18) | $field}]
  if {!($i & 128)} { return [list $field $wire] }
  # == == == == == == == == == == == == == == == == == == == == == == == == =

  binary scan $BUFFER ca* i BUFFER
  if {!($i & 128)} {  ;# (192==128+64):  bits 8, 7 are not set. (positiv int32)
    set x [expr {((127 & $i) << 25) | $field}]
    return [list $field $wire]
  }
  throw SPEC_ERROR "*** Spec says we never should reach here!"
}

::oo::define ::bpacket::reader method uint64 {} {
  binary scan $BUFFER ca* i0 BUFFER
  if {!($i0 & 128)} { return $i0 }

  # >>> generated code:  g1 0 10
  binary scan $BUFFER ca* i1 BUFFER
  if {!($i1 & 128)} { return [expr {(127 & $i0) | ($i1 << 7)}] }
  binary scan $BUFFER ca* i2 BUFFER
  if {!($i2 & 128)} { return [expr {(127 & $i0) | ((127 & $i1) << 7) | ($i2 << 14)}] }
  binary scan $BUFFER ca* i3 BUFFER
  if {!($i3 & 128)} { return [expr {(127 & $i0) | ((127 & $i1) << 7) | ((127 & $i2) << 14) | ($i3 << 21)}] }
  binary scan $BUFFER ca* i4 BUFFER
  if {!($i4 & 128)} { return [expr {(127 & $i0) | ((127 & $i1) << 7) | ((127 & $i2) << 14) | ((127 & $i3) << 21) | ($i4 << 28)}] }
  # <<< generated code

  binary scan $BUFFER ca* i BUFFER
  set x [expr {(127 & $i0) | ((127 & $i1) << 7) | ((127 & $i2) << 14) | ((127 & $i3) << 21) | ((127 & $i4) << 28) | ((127 & $i) << 35)}]
  if {!($i & 128)} { return $x }

  set shift 35; set n 6; set times 0
  while {$i & 128 && $times < 120} {
    binary scan $BUFFER ca* i BUFFER
    incr n
    set x [expr {((127 & $i) << [incr shift 7]) | $x}]
    incr times
  }
  if {$times >= 1200} {
    throw error "Malformed Packet"
  }
  return $x
}

::oo::define ::bpacket::reader method bool {} {
  binary scan $BUFFER ca* bool BUFFER
  return $bool
}

::oo::define ::bpacket::reader method varint {} {
  set shift -7
  set n 0 ; set x 0 ; set i 128
  set times 0
  while { $i & 128 && $times < 120 } {
    incr n
    binary scan $BUFFER ca* i BUFFER
    set x [expr { ( (127 & $i ) << [incr shift 7] ) | $x }]
    incr times
  }
  if {$times >= 1200} {
    throw error "Malformed Packet"
  }
  return $x
}

::oo::define ::bpacket::reader method string {} {
  set int [my varint]
  binary scan $BUFFER a${int}a* data BUFFER
  return $data
}
::oo::define ::bpacket::reader method hex {} {
  binary scan $BUFFER H* hex
  return $hex
}

# get each data piece
::oo::define ::bpacket::reader method next {} {
  if { [string equal [string range $BUFFER 0 1] \x00\x00] } {
    # Is another packet possibly available?
    #puts [string bytelength $BUFFER]
    if { [string bytelength $BUFFER] > 4 } {
      # If we have more data, we move to the next packet
      set BUFFER [string range $BUFFER 2 end]
      return [list 2]
    }
    return [list 0]
  }
  if { [string bytelength $BUFFER] <= 3 } {
    return 0
  }
  set id   [my varint]
  set type [my varint]
  #puts "ID: $id - Wire Type: $type"
  switch -- $type {
    0 { # varint | int32, int64, uint32, uint64, sint32, sint64, bool, enum
      set data [my varint]
    }
    2 { # Length-Delimited Data
      set data [my string]
    }
    15 { # Boolean
      set data [my bool]
    }
    16 { # Flags - A list of varints prefixed by the list length.
      set length [my uint64]
      set data   [list]
      while {$length > 0} {
        lappend data [my uint64]
        incr length -1
      }
    }
    17 - 18 {
            # 17 - List - A field of length delimited values prefixed by list length.
            # 18 - Keyed Dictionary - $varint $value - where $varint is key
            #      This works similar to list except it is converted to a
            #      dictionary on the other end based on the given keys.
      set length [my varint]
      set data   [list]
      while {$length > 0} {
        lappend data [my string]
        incr length -1
      }
    }
    19 { # Container - a container simply wraps values in a length-delimited
         #             fashion.
    }
    20 { # raw - we have raw bytes to read
      set data [my string]
    }
    21 {  # AES Encrypted with pre-shared key
          # TODO: Possibly encrypt the data using a configured
          #       encryption key.
      set data [my string]
    }
    default {
      throw MALFORMED_PACKET "Malformed Packet"
    }
  }
  return [list 1 $id $type $data]
}
