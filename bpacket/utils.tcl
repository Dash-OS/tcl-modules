namespace eval ::bpacket {}
namespace eval ::bpacket::decode {}

# parses the template syntax to produce a dict
# see bpacket/utils.tcl for formatting.
variable ::bpacket::parse_template_re {(?x)
  ^\s*(?=[0-9])  # our next value always begins with a number at the
                 # start of a line
  \s*([0-9]*)    # our field_id
  \s*(\*)?       # is the value required?
  \s*([^\s]*)    # the wire type
  \s*([^\s]*)    # our type_name value

  (?:               # optional type arguments which can be used by a type to
    (?=\s*\||\{)    # help encode/decode a value.  
    \s*(?:\|)?
    (
      (?:            # when arguments need multi-line they may wrap the arguments
        (?=\s*["\{])  # in "" or {}
        (?:\s*"[^"]*")  # everything between ""
        |                # or
        (?:\s*\{[^\}]*)\}  # everything between {}
      )
      |             # OR, we expect a simple list of values up until EOL
      (?:[^\n]+)
    )
  )?
  (?:              # optionally provided a field version
    (?=\s*\=)
    \s*\=\s*([0-9]*)
  )?
  (.*)           # the rest of the template for further parsing
}

if 0 {
  @ bpacket template | $template
    parses a bpacket template into a tcl dict which can then be
    parsed and encoded/decoded by a io class.

  @returns {TclBPTemplate}

  @type TclBPTemplate {dict}
    @key | types  {list<bpacket::type>}
    @key | fields {dict<TclBPTemplateFields>}

  @type TclBPTemplateFields {dict}
    A dict composed of each field from the template.
    @key   field_id {entier}
    @value field    {dict<TclBPTemplateField>}

  @type TclBPTemplateField {dict}
    A dict which describes a given type
    @key   | required {boolean}
      Is this field required when encoding/decoding?
    @key   | type     {bpacket::type}
      The fields wire id - used to decode/encode based upon
      the given type and arguments
    @key   | name     {string}
      The name of the type that the field represents.
    @key   | args     {any}
      Any args for this field that will modify how the
      given type encodes/decodes.
}
proc ::bpacket::template template {
  set index  [dict create]
  set fields [dict create]
  set types  [list]
  # parse the template and convert to dict
  while {[regexp -- $::bpacket::parse_template_re $template matched \
      field_id required type name args version \
        template
  ]} {
    if {$required eq "*"} {
      set required true
    } else { set required false }

    if {$version eq {}} {
      set version 0
    }

    set args [string trim $args " \t\n\"\{\}"]

    dict set fields $field_id [dict create \
      required $required \
      type     $type \
      name     $name \
      version  $version
    ]

    if {$args ne {}} {
      dict set fields $field_id args $args
    }

    dict set index $name $field_id

    if {$type ni $types} { lappend types $type }
  }

  return [dict create \
    fields $fields \
    types  $types \
    index  $index
  ]
}

if 0 {
  @ bpacket wrapstart | $data
}
proc ::bpacket::wrapstart data {
  set length [string length $::bpacket::HEADER]
  # if the string is wrapped, checked if the value right after it is
  # also a wrapper
  binary scan $data a${length} wrapper
  # puts $a
  if {[info exists wrapper] && [string equal $wrapper $::bpacket::HEADER]} {
    # the first character is the wrapper
    return true
  }
  return false
}

if 0 {
  @ bpacket headerstart | $data
    searches the value for $::bpacket::HEADER and returns the index
    when this is called we are looking for the "start" wrapper and
    are trashing everything else that may precede it since we don't
    have the bytes required to complete the previous packet.

    returns either an empty string or the packet with preceeding junk
    removed, signaling the start of a bpacket.
}

proc ::bpacket::headerstart data {
  set length [string length $::bpacket::HEADER]
  set idx    [string first $::bpacket::HEADER $data]
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


if 0 {
  @ bpacket register $type $id
    Used by each type to register itself
    for use by templates.  The $id must be
    unique and not overlap with any other
    type unless $false is set to {true}

  NOTE: Since the id and type needs to be identical
        on both ends of the wire, we cant auto generate
        the id value.  There may be a cleaner way of doing
        this which is more friendly to extensions.
}
proc ::bpacket::register {type id {force false}} {
  if {[dict exists $::bpacket::REGISTRY $type]} {
    if {!$force} {
      return \
        -code error \
        -errorCode [list BINARY_PACKET REGISTER_TYPE TYPE_EXISTS $type] \
        " tried to register a type (${type} / ${id}) which was already registered, did you mean to set force (3rd argument) to true?"
    } else {
      set replace [dict get $::bpacket::REGISTRY $type]
      dict unset ::bpacket::REGISTRY $replace
      if {[info command ::bpacket::type::$type] ne {}} {
        ::bpacket::type::$type destroy
      }
    }
  }
  if {[dict exists $::bpacket::REGISTRY $id]} {
    if {!$force} {
      return \
        -code error \
        -errorCode [list BINARY_PACKET REGISTER_TYPE TYPE_EXISTS $type] \
        " tried to register a type $type with id $id which was already registered to type [dict get $::bpacket::REGISTRY $id], did you mean to set force (3rd argument) to true?"
    } else {
      set replace [dict get $::bpacket::REGISTRY $id]
      dict unset ::bpacket::REGISTRY $replace
      if {[info command ::bpacket::type::$replace] ne {}} {
        ::bpacket::type::$replace destroy
      }
    }
  }

  dict set ::bpacket::REGISTRY $type $id
  dict set ::bpacket::REGISTRY $id   $type
}


package require tcc4tcl

set tcc4tcl [tcc4tcl::new]

$tcc4tcl ccode {
  #include <stdio.h>
  #include <stdint.h>

  int encode_unsigned_varint(uint8_t *const buffer, uint64_t value)
  {
    printf("starting\n");
      int encoded = 0;

      do
      {
          uint8_t next_byte = value & 0x7F;
          value >>= 7;

          if (value)
              next_byte |= 0x80;

          buffer[encoded++] = next_byte;

      } while (value);


      return encoded;
  }
}

$tcc4tcl cproc test {Tcl_Interp* interp long value} ok {
  char* buffer[10];
  encode_unsigned_varint(*buffer, value);

  Tcl_SetObjResult(interp, Tcl_NewStringObj(*buffer, -1));

  return (TCL_OK);
}


$tcc4tcl go
