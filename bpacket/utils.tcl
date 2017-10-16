namespace eval ::bpacket {}
namespace eval ::bpacket::decode {}

if 0 {
  @ bpacket template parsing
    parses the template syntax to produce a dict.  each bpacket
    field in a template follows:
    $field_id $type $name | ...$args

    where the "pipe" indicates the start of arguments.

    multi-line arguments are possible with {} in which case the
    pipe can also be omitted if desired.
}
variable ::bpacket::parse_template_re {(?x)
  ^\s*(?=[0-9])  # our next value always begins with a number at the
                 # start of a line
  \s*([0-9]*)    # our field_id
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
  while {[regexp -- $::bpacket::parse_template_re $template -> \
      field_id type name args version \
        template
  ]} {
    # version is not actually used by any types yet but it is
    # parsed by adding "= $version" to any field.
    if {$version eq {}} {
      set version 0
    }

    set args [string trim $args " \t\n\"\{\}"]

    dict set fields $field_id [dict create \
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
    checks to see if our bpacket header is at the start of our data
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
    searches the value for $::bpacket::HEADER and returns the data
    starting with the header value and forward, removing anything that
    may be preceeding it.

    returns either an empty string or the packet with preceeding junk
    removed, signaling the start of a bpacket (but not necessarily a complete).
}
proc ::bpacket::headerstart data {
  set idx [string first $::bpacket::HEADER $data]
  # puts "bpacket header start: $idx"
  if {$idx == -1} {
    # we could not find the wrapper in the given string
    return
  }
  if {$idx != 0} {
    return [string range $data $idx end]
  } else {
    return $data
  }
}

proc ::bpacket::trimheader data {
  return [string trimleft $data $::bpacket::HEADER]
}

proc ::bpacket::nextheader data {
  # ignore a current header and move to the next one, if possible
  return [::bpacket headerstart [::bpacket trimheader $data]]
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
