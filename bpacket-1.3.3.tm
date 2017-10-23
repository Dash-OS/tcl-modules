if 0 {
  @ bpacket @
    binary packet is used to encode and decode data in a way that
    is similar to protocol buffers.

    it is composed of various parts.  data is encoded using a given
    template and the template is used on each end to encode/decode
    for communication.

  @type BPTemplate
    | This builds our binary format template.  It is utilized by both the
    | encoding and decoding end to understand how to build and parse our
    | binary packets automatically.
  TODO:
    * asterix items are marked as required, although this is not
    * currently enforced.

    > Format
      {(*)? (type_name) (...type_args) | (field_num)}
  @example
  {
    set template {
      1  flags   props | type channel
      2  string  hid
      3  string  sid
      4  numlist nlist | known
      5  varint  timestamp
      6  list    protocols
      7  string  ruid
      8  string  op
      9  raw     raw
      10 list    tags
      11 boolean keepalive
      12 list    filter
      13 string  error
      14 dict    data | {
        first_name
        last_name
        phone_number
        address
        employer
      }
    }
    set data [dict create \
      timestamp [clock microseconds] \
      hid       00:00:00:00:00:00 \
      sid       a-7898 \
      props     [list 0 10] \
      protocols [list a b c] \
      ruid      MY_EVENT \
      keepalive 1 \
      data [dict create \
        first_name john \
        last_name  smith \
        phone_number 6665554444 \
        address "Some address can go here" \
        employer "Acme, Inc"
      ]
    ]
  }
}

set template {
  1 boolean compact
  2 varint schema
}

namespace eval ::bpacket {
  namespace ensemble create
  namespace export {[a-z]*}

  # the value used to indiciate the start of the header
  variable HEADER "\xC0\x8D"
  # end of packet - should not be the same as HEADER as we
  # will remove any number of $EOF THEN look for HEADER to
  # determine if we have multiple packets concatted
  variable EOF "\x00\x00"

  # holds a hash map of $id -> $type and $type -> $id
  # of types that have been registered.
  #
  # types are required & registered when they are required by a template
  if {![info exists ::bpacket::REGISTRY]} {
    variable REGISTRY [dict create]
  }

  # these types are required and will be required automatically
  # regardless of the given template.
  variable REQUIRED_TYPES [list varint string]
}

namespace eval ::bpacket::decode {
  namespace ensemble create
  namespace export {[a-z]*}
}

namespace eval ::bpacket::encode {
  namespace ensemble create
  namespace export {[a-z]*}
}

namespace eval ::bpacket::type {
  namespace ensemble create
  namespace export {[a-z]*}
}

source -encoding utf-8 [file join \
  [file dirname \
    [file normalize [info script]] \
  ] \
  bpacket \
  utils.tcl
]

if 0 {
  @ bpacket create | $type $name ...$args
    Allows creation of the various bpacket classes
  @arg type {io|stream}
    @type {io}
      creates a bpacket io object which is responsible for both
      encoding and decoding bpackets
    @type {stream}
      creates a bpacket stream object which receives a stream of
      data and outputs valid bpackets when they are found
  @arg name {string}
  @arg args
    @if | $type {io}
      @arg template {BPTemplate}
        the template that the given io handler should use.
}
proc ::bpacket::create {type name args} {
  switch -nocase -- $type {
    io {
      package require bpacket::classes::io
    }
    stream {
      package require bpacket::classes::stream
    }
  }
  tailcall ::bpacket::classes::[string tolower $type] create $name {*}$args
}
