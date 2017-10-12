package require tcl::chan::events
package require ensembled

namespace eval ::bpacket {ensembled}
namespace eval ::bpacket::decode {ensembled}

variable ::bpacket::WRAPPER "\xC0\x8D"

proc ::bpacket::decode::varint data {
  # remove our wrapper value before parsing any varint
  # our cursor indicates the location where the data
  # begins and the varint completes, including the removal
  # of any WRAPPER values.
  set cursor 0
  set wrapper_length [string length $::bpacket::WRAPPER]
  while {[string match ${::bpacket::WRAPPER}* $data]} {
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

# checks if the data is wrapped in the $::bpacket::WRAPPER
proc ::bpacket::wrapstart data {
  set length [string length $::bpacket::WRAPPER]
  # if the string is wrapped, checked if the value right after it is
  # also a wrapper
  binary scan $data a${length} wrapper
  # puts $a
  if {[info exists wrapper] && [string equal $wrapper $::bpacket::WRAPPER]} {
    # the first character is the wrapper, however this may be
    # the end of one and the start of another
    return true
  }
  return false
}

# searches the value for $::bpacket::WRAPPER and returns the index
# when this is called we are looking for the "start" wrapper and
# are trashing everything else that may precede it since we don't
# have the bytes required to complete the previous packet.
#
# returns either an empty string or the packet with preceeding junk
# removed, signaling the start of a bpacket.
proc ::bpacket::headerstart data {
  set length [string length $::bpacket::WRAPPER]
  set idx    [string first $::bpacket::WRAPPER $data]
  if {$idx == -1} {
    # we could not find the wrapper in the given string
    return
  }
  if {$idx == 0} {
    set buf $data
  } else {
    set buf [string range $data $idx end]
  }
  return $buf
}

::oo::class create ::bpacket::stream {}

::oo::define ::bpacket::stream {
  variable STATUS BUFFER PACKETS CHAN CALLBACK
  # when building a chunked packet we will populate these values indicating
  # what we are expecting in terms of packet length.
  #
  # NEXT_SIZE  = expected [string length] of packet (not including wrapper)
  # NEXT_START = index of where our packet starts relative to BUFFER index 0
  variable NEXT_SIZE NEXT_START
}

::oo::define ::bpacket::stream constructor {} {
  set NEXT_SIZE  -1
  set NEXT_START -1
  set CALLBACK   {}
  set CHAN       {}
  set BUFFER     {}
  set STATUS     NEW
  set PACKETS    [list]
}

::oo::define ::bpacket::stream destructor {

}

::oo::define ::bpacket::stream method use chan {
  if {$CHAN eq {}} {
    set CHAN $chan
    coroutine [namespace current]::runner my Run
  } elseif {$CHAN ne $chan} {
    return \
      -code error \
      -errorCode [list BINARY_PACKET STREAM STREAM_UNAVAILABLE] \
      " a chan has already been applied to [self] : $CHAN - tried to apply $chan"
  }
  return
}

::oo::define ::bpacket::stream method Status {status args} {
  set STATUS $status
}

::oo::define ::bpacket::stream method event callback {
  set CALLBACK $callback
}

::oo::define ::bpacket::stream method prop prop {
  return [set [string toupper $prop]]
}

# When append is called, we will add more data to the buffer
# and attempt to build a fully formed packet.
::oo::define ::bpacket::stream method append data {
  set initial [expr {[string length $BUFFER] == 0}]
  if {$initial} {
    # this is the initial data and we can begin parsing
    # for complete bpackets.
    if {![::bpacket::wrapstart $data]} {
      # bpacket is wrapped with $::bpacket::WRAPPER, check for the
      # value within the data and ignore anything else that may
      # precede it.  if a header can not be found then we will
      # end up appending nothing to the buffer value.
      append BUFFER [::bpacket::headerstart $data]
    } else {
      # if we are at the start of a packet, add it!
      append BUFFER $data
    }
  } else {
    # if this is not the first append of data then we
    # are waiting on additional data to complete our
    # bpacket.
    append BUFFER $data
  }
  # at this point, if our buffer has any data in it, we will attempt
  # to parse the buffer into packets which can be dispatched
  my flush
}

# flush the buffer by attempting to read the current buffer and attempt
# to capture a complete packet
::oo::define ::bpacket::stream method flush {} {
  if {$BUFFER ne {}} {
    # here we want to verify that our BUFFER starts with our
    # wrapper value.  if something gets messed up in some way
    set BUFFER [bpacket headerstart $BUFFER]
    while {$BUFFER ne {} && [bpacket wrapstart $BUFFER]} {
      # the start of the buffer is already validated at this point.
      # check if the length has been parsed from the buffer yet, if
      # not then we check it.
      #
      # bpackets are encapsulated within a length-delimited binary
      # field.  multiple packets may be chained together and we
      # may receive the packets in chunks.
      #
      # $WRAPPER$length$packet\x00$WRAPPER$length$packet\x00 ...
      #
      # a complete packet will encounter either another $WRAPPER value
      # or it will be the EOF / end of the buffer value.  If we do not
      # match up the packet is malformed.
      if {$NEXT_SIZE == -1} {
        lassign [bpacket decode varint $BUFFER] NEXT_SIZE NEXT_START
      }

      set packet_length [expr {[string length $BUFFER] - $NEXT_START - 1}]

      # puts "$packet_length vs expected $NEXT_SIZE"

      if {$packet_length == $NEXT_SIZE && [string equal [string index $BUFFER end] \x00]} {
        # This is the best case scenario, in this case
        # we can be almost certain our $BUFFER consistutes
        # one single bpacket.
        #
        # We validate the data by confirming a NULL is discovered
        # terminating the packet
        lappend PACKETS $BUFFER
        set BUFFER {}
      } elseif {$packet_length > $NEXT_SIZE} {
        # We have received more data with this addition
        # than the packet length should be.  Here we need
        # to be careful and make sure that we only
        # add the data if we can validate its integrity.
        #
        # When we received more data than expected we should
        # resemble the above example of chunked packets.
        #
        # Here we need to take care as we assemble the packet to
        # try to piece the packets together as they arrive within our
        # stream.
        #
        # Should we grab a packet and not find our wrapper on the next
        # bytes, we need
        set packet [string range $BUFFER 0 [expr {$NEXT_START + $NEXT_SIZE}]]
        set BUFFER [string range $BUFFER [expr {$NEXT_START + $NEXT_SIZE + 1}] end]

        # $packet should now begin with our wrapper and end with a NULL.
        if {[string equal [string index $packet end] \x00]} {
          # Our packet has been verified!
          lappend PACKETS $packet
        } else {
          # Should we not find a NULL character at the end of $packet
          # then we must assume that packets were received out of order
          # or in a malformed data format.
          #
          # In this case we are going to need to drop a packet most likely.
          # We need to rebuild our original buffer and search for the next
          # start packet minus the initial $WRAPPER
          #
          # Then we search for the next header within our current data.
          # if found, we will trash everything up to it and continue
          # parsing from that point, hoping that we will be able to
          # assemble the packets properly moving forward.
          #
          # TODO: If we want to enhance the reliability of the handling here
          #       there should be some simple adjustments to the wire protocol
          #       that will allow a tcp-like ordering of packets.  Additionally,
          #       we should be able to build models that can attempt to "assemble"
          #       the blocks that we have received and make them fit to create a
          #       proper bpacket format.
          set BUFFER [bpacket headerstart \
            [string trimleft $packet$BUFFER $::bpacket::WRAPPER]
          ]
        }
      } else {
        # We have received a partial packet.  In this case
        # we simply have to wait for more data to be appended.
        break
      }
      # if we are continuing to the next loop
      # we must reset our size and start values.
      set NEXT_SIZE  -1
      set NEXT_START -1
    }
    # Now that we have finished parsing our received binary data,
    # we check if we have any packets within our PACKETS list and
    # dispatch them to our callback
    my Dispatch
  }
}

::oo::define ::bpacket::stream method Dispatch {} {
  set results [list]
  while {[llength $PACKETS]} {
    try {
      set PACKETS [lassign $PACKETS packet]
      lappend results [::cluster::packet::decode $packet]
    } on error {result options} {
      # When we do encounter a malformed packet, we will handle
      # the error before passing it to the user?
      # TODO: ?
    }
  }
  return $results
}

::oo::define ::bpacket::stream method Run args {
  after 0 [info coroutine]
  yield   [info coroutine]
  my Status RUNNING

  chan configure $CHAN \
    -blocking    0 \
    -translation binary \
    -buffering   none

  chan event $CHAN readable [list [info coroutine] READ]

  while {$STATUS ne "CLOSED"} {
    set action [yield]
    switch -- $action {
      READ {
        if {[chan eof $CHAN]} {
          # Our channel has been closed
          chan close $CHAN
          my Status CLOSED
        }
        # Adds data to the buffer
        my append [chan read $CHAN]
      }
    }
  }
}
