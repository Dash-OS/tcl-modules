# provides a utility to read varint values outside of the
# reader context - returning a list of elements
# $varint $cursor $remaining
proc ::bpacket::decode::varint data {
  # remove our wrapper value before parsing any varint
  # our cursor indicates the location where the data
  # begins and the varint completes, including the removal
  # of any WRAPPER values.
  set cursor 0
  set wrapper_length [string length $::bpacket::HEADER]
  while {[string match ${::bpacket::HEADER}* $data]} {
    # we need to count how many times we shift so we can
    # return the index for the start of the data from our
    # current position
    incr cursor $wrapper_length
    set data [string range $data ${wrapper_length} end]
  }
  set shift -7
  set x 0 ; set i 128
  set times 0
  while { $i & 128 && $times < 1000 } {
    binary scan $data ca* i data
    set x [expr { ( (127 & $i ) << [incr shift 7] ) | $x }]
    incr times
  }
  if {$times >= 1200} {
    tailcall return \
      -code error \
      -errorCode [list BINARY_PACKET READ MALFORMED_PACKET STACK_OVERFLOW] \
      " bpacket encountered a malformed packet while reading a varint value"
  }
  return [list $x [expr {$cursor + $times}] $data]
}

::oo::define ::bpacket::reader {
  variable PACKET BUFFER EXPECTED_LENGTH
  # by providing a template, we can automatically
  # decode data and provide it to the caller
  variable TEMPLATE
}

::oo::define ::bpacket::reader constructor {{packet {}} {template {}}} {
  if {$template ne {}} {
    my template $template
  } else {
    set TEMPLATE {}
  }
  if {$packet ne {}} {
    my set $packet
  } else {
    set BUFFER {}
    set PACKET {}
  }
}

::oo::define ::bpacket::reader method template {template} {
  set TEMPLATE $template
}

::oo::define ::bpacket::reader method reset {} {
  set BUFFER $PACKET
}

::oo::define ::bpacket::reader method set packet {
  if {![string match "${::bpacket::HEADER}*" $packet]} {
    tailcall return \
      -code error \
      -errorCode [list BINARY_PACKET READ VALIDATE INVALID_HEADER] \
      " the received packet does not appears to start with the expected header value"
  }
  set PACKET $packet
  set BUFFER $packet
  set BUFFER [string trimleft $BUFFER $::bpacket::HEADER]
  set EXPECTED_LENGTH [my varint]
}

::oo::define ::bpacket::reader method field {} {
  binary scan $BUFFER ca* i BUFFER

  set field [expr {($i & 120) >> 3}]
  set wire [expr {$i & 7}]

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
    tailcall return \
      -code error \
      -errorCode [list BINARY_PACKET READ MALFORMED_PACKET STACK_OVERFLOW] \
      " bpacket encountered a malformed packet while reading a uint64 value"
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
  while { $i & 128 && $times < 1000 } {
    incr n
    binary scan $BUFFER ca* i BUFFER
    set x [expr { ( (127 & $i ) << [incr shift 7] ) | $x }]
    incr times
  }
  if {$times >= 1200} {
    tailcall return \
      -code error \
      -errorCode [list BINARY_PACKET READ MALFORMED_PACKET STACK_OVERFLOW] \
      " bpacket encountered a malformed packet while reading a varint value"
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
  if { [string match "${::bpacket::EOF}*" $BUFFER] } {
    # Is another packet possibly available? Remove a single
    # EOF - EOF should never match HEADER.
    set BUFFER [string trimleft $::bpacket::EOF]
    if {$BUFFER ne {}} {
      # Now we will know if we have another packet to parse
      # if we have another HEADER at idx 0
      # If we don't then we unfortunately have no way of
      # parsing the remaining buffer
      if {[string match "${::bpacket::HEADER}*" $BUFFER]} {
        # yep - next packet is queued up and ready to go!
        return [list 2]
      } else {
        return [list 0 WARN TRAILING_TRASH [string length $BUFFER]]
      }
    }
    return [list 0]
  }

  if {[string trim $BUFFER] eq {}} {
    return [list 0]
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

proc ::cluster::packet::decode { packet {cluster {}} } {
  try {
    # ~! "Decode Packet" "Decoding a Packet [string bytelength $packet]"
    set reader  [::bpacket::reader new $packet]
    set result  [dict create]
    set results [list]
    set active 1
    while {$active} {
      lassign [$reader next] active id type data
      switch -- $active {
        0 {
          # We are done parsing the packet!
          lappend results $result
          break
        }
        1 {
            # We have more to parse!
            switch -- $id {
            1  {
              lassign $data type channel
              dict set result type $type
              dict set result channel $channel
            }
            2  { dict set result hid $data }
            3  { dict set result sid $data }
            4  { dict set result flags $data }
            5  { dict set result timestamp $data }
            6  { dict set result protocols $data }
            7  { dict set result ruid $data }
            8  { dict set result op $data }
            9  { dict set result data $data }
            10 { dict set result raw $data }
            11 { dict set result tags $data }
            12 { dict set result keepalive $data }
            13 {
              # When we receive a filter we will immediately try to check with the
              # cluster if our service matches and quit decoding immediately if we
              # dont.
              if { $cluster ne {} && ! [$cluster check_filter $data] } {
                break
              }
              dict set result filter $data
            }
            14 {
              dict set result error $data
            }
          }
        }
        2 {
          # We are done with a packet -- but another might still be
          # available!
          lappend results $result
          set result [dict create]
        }
      }
    }
    $reader destroy
  } on error {result options} {
    puts stderr "Malformed Packet! $result"
    catch { ::onError $result $options "Malformed Packet!" }
    catch { $reader destroy }
  }
  if { $active } {
    set result {}
  }
  return $results
}


::oo::define ::bpacket::reader method decode {{template {}}} {
  if {$template ne {}} {
    my template $template
  }

  if {$TEMPLATE eq {}} {
    return \
      -code error \
      -errorCode [list BINARY_PACKET READ DECODE MISSING_TEMPLATE] \
      " tried to decode a bpacket but have not provided a template, did you mean next?"
  }

  set result  [dict create]
  set results [list]
  set active  1
}
