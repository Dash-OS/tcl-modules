if {[info command ::bpacket::classes::stream] eq {}} {
  ::oo::class create ::bpacket::classes::stream {}
}

::oo::define ::bpacket::classes::stream {
  variable STATUS BUFFER PACKETS CHAN CALLBACK
  # when building a chunked packet we will populate these values indicating
  # what we are expecting in terms of packet length.
  #
  # NEXT_SIZE  = expected [string length] of packet (not including wrapper)
  # NEXT_START = index of where our packet starts relative to BUFFER index 0
  variable NEXT_SIZE NEXT_START
  # store timeouts / afterids to cancel when needed
  variable TIMEOUTS
}

::oo::define ::bpacket::classes::stream constructor args {
  set TIMEOUTS   [dict create]
  set PACKETS    [list]
  set STATUS     NEW
  set NEXT_SIZE  -1
  set NEXT_START -1
  if {[llength $args]} {
    foreach {arg value} $args {
      set [string toupper $arg] $value
    }
  }
  if {![info exists BUFFER]} {
    set BUFFER {}
  }
  if {![info exists CALLBACK]} {
    set CALLBACK {}
  }
  if {![info exists CHAN]} {
    set CHAN {}
  }
}

::oo::define ::bpacket::classes::stream destructor {
  dict for {name id} $TIMEOUTS {
    after cancel $id
  }
  if {[info command [namespace current]::runner] ne {}} {
    [namespace current]::runner CLOSING
  }
  # safety check
  if {$CHAN ne {} && $CHAN in [chan names]} {
    catch { chan close $CHAN }
  }
}

::oo::define ::bpacket::classes::stream method use chan {
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

::oo::define ::bpacket::classes::stream method Status {status args} {
  set STATUS $status
}

::oo::define ::bpacket::classes::stream method event callback {
  set CALLBACK $callback
  dict set TIMEOUTS dispatch [after 0 [namespace code [list my Dispatch]]]
}

::oo::define ::bpacket::classes::stream method prop prop {
  return [set [string toupper $prop]]
}

# When append is called, we will add more data to the buffer
# and attempt to build a fully formed packet.
::oo::define ::bpacket::classes::stream method append data {
  set initial [expr {[string length $BUFFER] == 0}]
  if {$initial} {
    # this is the initial data and we can begin parsing
    # for complete bpackets.
    if {![::bpacket::wrapstart $data]} {
      # bpacket is wrapped with $::bpacket::HEADER, check for the
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
  #
  # by doing this asynchronously we also allow more data to come in
  # if needed before flushing the data
  if {![dict exists $TIMEOUTS flush]} {
    dict set TIMEOUTS flush [after 0 [namespace code [list my flush]]]
  }
}

# flush the buffer by attempting to read the current buffer and attempt
# to capture a complete packet
::oo::define ::bpacket::classes::stream method flush {} {
  if {[dict exists $TIMEOUTS flush]} {
    after cancel [dict get $TIMEOUTS flush]
    dict unset TIMEOUTS flush
  }
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

      set eof_length [string length $::bpacket::EOF]

      set packet_length [expr {[string length $BUFFER] - $NEXT_START - $eof_length}]

      # puts "$packet_length vs expected $NEXT_SIZE"

      if {$packet_length == $NEXT_SIZE && [string match "*${::bpacket::EOF}" $BUFFER]} {
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
        set packet [string range $BUFFER 0 [expr {$NEXT_START + $NEXT_SIZE + $eof_length - 1}]]
        set BUFFER [string range $BUFFER [expr {$NEXT_START + $NEXT_SIZE + $eof_length}] end]

        # $packet should now begin with our wrapper and end with a NULL.
        if {[string match "*${::bpacket::EOF}" $BUFFER]} {
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
            [string trimleft $packet$BUFFER $::bpacket::HEADER]
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

::oo::define ::bpacket::classes::stream method reset {} {
  set BUFFER     {}
  set NEXT_SIZE  -1
  set NEXT_START -1
}

::oo::define ::bpacket::classes::stream method Dispatch {} {
  # cancel any timeouts that may be scheduled already
  if {[dict exists $TIMEOUTS dispatch]} {
    after cancel [dict get $TIMEOUTS dispatch]
    dict unset TIMEOUTS dispatch
  }
  while {[llength $PACKETS]} {
    try {
      set PACKETS [lassign $PACKETS packet]
      {*}$CALLBACK $packet
    } on error {result options} {
      # When we do encounter a malformed packet, we will handle
      # the error before passing it to the user?
      # Until we know how to handle this, we will rethrow it
      # TODO: ?
      throw error $result
    }
  }
}

# channel handling here is completely optional - if not used
# you can simply copy what this is doing by calling
# $stream append $pkt
::oo::define ::bpacket::classes::stream method Run args {
  dict set TIMEOUTS initialize [after 0 [list catch [list [info coroutine]]]
  yield [info coroutine]

  my Status RUNNING

  chan configure $CHAN \
    -blocking    0 \
    -translation binary \
    -buffering   none

  chan event $CHAN readable [list catch [list [info coroutine] READ]]

  while {$STATUS ne "CLOSED"} {
    set args [lassign [yield] action]
    switch -- $action {
      CLOSING {
        catch { chan close $CHAN }
        my Status CLOSED
      }
      READ {
        if {[chan eof $CHAN]} {
          # Our channel has been closed
          catch { chan close $CHAN }
          my Status CLOSED
        }
        # Adds data to the buffer
        my append [chan read $CHAN]
      }
    }
  }
}
