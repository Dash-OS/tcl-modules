if 0 {
  @ bpacket::class::io @
    read/write your binary template
}
if {[info command ::bpacket::classes::io] eq {}} {
  ::oo::class create ::bpacket::classes::io {}
}

::oo::define ::bpacket::classes::io {
  # the template enables us to encode/decode.  it should
  # be identical on both ends of the wire.
  variable TEMPLATE
  # TYPES holds the current list of types
  variable TYPES
  # holds the buffer for encoded values
  variable ENCODE_BUFFER
  # holds the buffer for decoded values
  variable DECODE_BUFFER
}

::oo::define ::bpacket::classes::io constructor template {
  set ENCODE_BUFFER {}
  set DECODE_BUFFER {}
  my template $template
  my @reset::types
}

::oo::define ::bpacket::classes::io method template template {
  set TEMPLATE [bpacket template $template]
  my @reset::types
}

::oo::define ::bpacket::classes::io method reset {} {
  my @reset::types
}

::oo::define ::bpacket::classes::io method @reset::types {} {
  my @reset::mixins

  # build a list of types that are required.  if they are
  # not yet added then they will be lappended to $TYPES
  # when we require them.
  set types [list \
    {*}$::bpacket::REQUIRED_TYPES \
    {*}[dict get $TEMPLATE types]
  ]

  # require each type - this will initialize and mixin when needed,
  # duplicate requires will be ignored.
  my requires {*}$types
}

::oo::define ::bpacket::classes::io method @reset::mixins {} {
  # clear any current mixins and reset
  ::oo::objdefine [self object] mixin -clear
  set TYPES [list]
}

if 0 {
  @ io requires | ...types
    When a type requires another type, it may call [my requires] within
    its init method.  This will check if the type is currently available
    and if it isn't, it will attempt to require and mix it in.

    Each type should either be a package within bpacket/type or it should
    be defined within the ::bpacket::type namespace by its name so that
    it can be mixed in.  If it is not available, an error is thrown.
}
::oo::define ::bpacket::classes::io method requires args {
  foreach type $args {
    if {$type in $TYPES} { continue }
    if {![my can @encode::$type]} {
      # allow user to define types themselves within the namespace
      # at runtime
      catch { package require bpacket::type::$type }
      if {[info command ::bpacket::type::$type] ne {}} {
        ::oo::objdefine [self] mixin -append ::bpacket::type::$type
        # if the mixin has a @init method then we will call it
        if {[my can @init::$type]} {
          if {[catch {my @init::$type} err]} {
            return \
              -code error \
              -errorCode [list BINARY_PACKET REQUIRE_TYPE TYPE_INIT_ERROR $type] \
              " failed to initialize the bpacket type ${type}, an error occurred during initialization: $err"
          }
        }
      } else {
        return \
          -code error \
          -errorCode [list BINARY_PACKET REQUIRE_TYPE TYPE_NOT_FOUND $type] \
          " a bpacket type requires type $type but it was not found in the ::bpacket::type namespace"
      }
    }
    lappend TYPES $type
  }

  unset -nocomplain ::bpacket::type::current
}

if 0 {
  @ io can | method
    Allows checking to see if a specific value has been made
    available.  Useful when checking if a mixin is present and
    valid.
  @example
  {
    if {[my can @encode::varint]} {
      #...
    }
  }
}
::oo::define ::bpacket::classes::io method can method {
  set methods [info object methods [self] -all -private]
  if {$method in $methods} {
    return true
  } else {
    return false
  }
}

::oo::define ::bpacket::classes::io method encode data {
  set ENCODE_BUFFER {}

  dict for {name value} $data {
    if {[dict exists $TEMPLATE index $name]} {
      set field_id [dict get $TEMPLATE index $name]
      set field [dict get $TEMPLATE fields $field_id]
      append ENCODE_BUFFER [my @write::field $field_id $field $value]
    } else {
      throw error "Encoding Failed: $name is not a known field"
    }
  }

  append encoded \
    $::bpacket::HEADER \
    [my @encode::varint [string length $ENCODE_BUFFER]] \
    $ENCODE_BUFFER \
    $::bpacket::EOF

  set ENCODE_BUFFER {}

  return $encoded
}

::oo::define ::bpacket::classes::io method @write::field {field_id field value} {
  set type [dict get $field type]
  # Encoding a field is handled by the type mixins which have been included.
  # Each field is formatted starting with its field number followed by its
  # encoded value.
  #
  # the decoder will then be able to read the field number and compare it
  # with its template to determine how to properly decode the packet.

  # We deviate from protocol buffers here to allow any wire_type here.  Since
  # we are accepting values above 12(?)+- we can not follow their protocol
  # directly.
  append encoded \
    [my @encode::varint $field_id] \
    [my @encode::$type $value $field]
}

::oo::define ::bpacket::classes::io method decode {packet args} {
  # first we need to validate that we have a valid packet.
  if {![string match "${::bpacket::HEADER}*" $packet]} {
    return \
      -code error \
      -errorCode [list BINARY_PACKET DECODE MALFORMED_PACKET INVALID_HEADER] \
      " attempted to decode a bpacket which does not have a valid header"
  } elseif {![string match "*${::bpacket::EOF}" $packet]} {
    return \
      -code error \
      -errorCode [list BINARY_PACKET DECODE MALFORMED_PACKET INVALID_FOOTER] \
      " attempted to decode a bpacket which does not have a valid footer"
  }

  set DECODE_BUFFER [string range $packet [string length $::bpacket::HEADER] end-[string length $::bpacket::EOF]]

  set packet_length [my @decode::varint]

  set DECODE_BUFFER [string range $DECODE_BUFFER 0 ${packet_length}+1]

  if {"-while" in $args} {
    # shimmer shimmer
    set while [dict get $args -while]
  }

  set result [dict create]

  while {$DECODE_BUFFER ne {}} {
    set field [my next]
    if {[info exists while]} {
      if {![{*}$while $field]} {
        set DECODE_BUFFER {}
        set result [dict create]
        break
      }
    }
    dict set result [dict get $field name] [dict get $field value]
  }

  return $result
}

::oo::define ::bpacket::classes::io method next {} {
  set field_id [my @decode::varint]
  if {![dict exists $TEMPLATE fields $field_id]} {
    return \
      -code error \
      -errorCode [list BINARY_PACKET DECODE UNKNOWN_FIELD $field_id] \
      " bpacket tried to decode a packet but encountered an unknown field with an id of $field_id"
  }
  set field [dict get $TEMPLATE fields $field_id]
  dict set field id    $field_id
  dict set field value [my @decode::[dict get $field type] $field]
  return $field
}
