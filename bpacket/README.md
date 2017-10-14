# bpacket (binary packet)

> Documentation is a work in progress

`[bpacket]` is a package that makes encoding & decoding compact binary packets to transmit your data on the wire or other bandwidth-sensitive situations.  It attempts to pack information as tightly as possible for transmission in many-to-many communication protocols like [tcl-cluster](https://github.com/Dash-OS/tcl-cluster).

## Binary Template

```tcl
# A bpacket template example
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

# a corresponding data value that could be encoded
set data [dict create \
  timestamp [clock microseconds] \
  hid       00:00:00:00:00:00 \
  sid       a-7898 \
  props     [list 0 10] \
  protocols [list a b c] \
  ruid      MY_EVENT \
  keepalive true \
  data [dict create \
    first_name john \
    last_name  smith \
    phone_number 6665554444 \
    address "Some address can go here" \
    employer "Acme, Inc"
  ]
]
```

Before we can encode/decode packets that `bpacket` will create for us, we need to provide it with a template which it will use.  This allows us to optimize and customize our packets to our specific use-case.

Our template provides us with a structure that allows us to optimize specific
values that may come up.  When encoding, a dict is expected that matches
the template "names".  An identical dict will be provided when decoding.

|  Type  |  Description  |
| :----------: |:----------- |
| varint | a [varint](https://developers.google.com/protocol-buffers/docs/encoding#varints)-like value which packs entier values as tightly as possible. |
| string | a utf-8 encoded string value |
| boolean | a boolean value |
| flags | a list of booleans prefixed by the list length, optionally with keys (dict values -> flags) |
| numlist | a list of varints prefixed by the list length, optionally with keys (dict values -> numlist) |
| float | a 32-bit or 64-bit float |
| vfloat | a (highly-experimental) method of encoding highly compact simple float values |
| list | a length-delimited list of strings |
| dict | a key/value pairing of values where only the values are encoded as a list, the keys are re-constructed when decoding.  all values encoded as string. |
| raw | a raw length-delimited value (no encoding or modification) |

```tcl
# request side
package require bpacket

set template {
  1 varint timestamp
  2 dict   request   | {
    id
    body
  }
  3 dict   response  | {
    id
    result
    body
  }
}

bpacket create io ::io $template

proc encode data {
  set encoded [io encode $req]

  # --> transmit binary request
}

encode [dict create \
  timestamp [clock seconds] \
  request   [dict create \
    id   my_request \
    body request!
  ]
]
```

```tcl
# response side
package require bpacket

set template {
  1 varint timestamp
  2 dict   request   | {
    id
    body
  }
  3 dict   response  | {
    id
    result
    body
  }
}

bpacket create io ::io $template

# receives encoded request
proc decode encoded {
  set decoded [io decode $encoded]

  set request [dict get $decoded request]

  # do something

  set res [dict create \
    timestamp [clock seconds] \
    response  [dict create \
      id       [dict get $request id] \
      result   ok  \
      body     response!
    ]
  ]

  set encoded [io encode $res]

  # transmit back to requester
}
```

## Encoding Notes

### varint

> Each byte in a varint, except the last byte, has the most significant bit (msb) set – this indicates that there are further bytes to come. The lower 7 bits of each byte are used to store the two's complement representation of the number in groups of 7 bits, least significant group first.
[...read more about varints](https://developers.google.com/protocol-buffers/docs/encoding#varints)

varint values are used to pack numbers are varied lengths as tightly as possible.
For example, comparing the [string length] of the value of [clock microseconds] at
the time of writing this (1508014884331554):

```tcl
# varint
package require bpacket

# require varint manually
package require bpacket::type::varint

set n 1508014884331554

set encoded [bpacket encode varint $n]
set raw_compressed [zlib compress $n]
set enc_compressed [zlib compress $encoded]

puts "
  Value: $n
  Raw Length:                [string length $n]
  Encoded Length:            [string length $encoded]
  Raw Compressed Length:     [string length $raw_compressed]
  Encoded Compressed Length: [string length $enc_compressed]
"
```

### boolean

0 or 1.  boolean values will take up a total of 2 bytes in most cases.

### flags

Flags may also be thought of as a "list of booleans", this is a length-delimited list of booleans following the pattern `$varint (llength) ...$boolean (flag)...`

How flags are expected to be presented depends on the template.  We will either
expect a raw list of booleans (`[list true false true]`) or a dict where each
key corresponds to a value in the fields args and its value being a boolean.

```tcl
set template {
  1 flags flags1
  2 flags flags2 | one two three
}

# would expect flags1 and flags2 to look like:
set data [dict create \
  flags1 [list false true true] \
  flags2 [dict create one false two true three true]
]
```

In the example above, providing arguments to the flags2 field allows us to  
translate the values on each end while still providing the same sized packet. However, flags1 does allow us to have a dynamic number of flags if needed.

### numlist

A numlist is identical to flags in how it works.  However, a numlist will encode
a list of varints prefixed by list length instead of booleans.  

> **Note**: Both numlist and flags are able to be significantly more efficient than
a standard list since they only require a single varint delimiter.

### list

lists are encoded as a length-delimited list of "strings" which match `$varint (llength) ...$varint (value length) $value (any) \x00...]`

### dict

dicts are encoded identically to lists.  However, the keys of the dict are removed
when encoded and added back when decoded.  When encoding a dict, all keys within the
the args value are required or an error will be thrown.

> **Note:** At this time dicts values are all encoded as strings.  In the future
this may change to allow templating deeper data structures.  This would allow a
tighter overall package (sometimes significantly so), but would also hit performance.

### raw

raw values are not utf-8 encoded and are added as their raw bytes to the packet.  they are provided as `$varint $bytes`

### vfloat

a highly experimental method of encoding floats that will likely fail for anything
that isn't a simple value.  This can, for example, be the most efficient method
for encoding percents.  

We achieve this by simply splitting the value by its decimal and encoding the
varint for each side.  We also encode whether the value is negative or positive
as the first byte.  

For example, the value "20.3" has an encoded length of 2 whereas using a standard
float guarantees a length of 4.  This difference can have a significantly more
drastic difference as the value and precision grows in size.  

We do not currently account for values that are not simple numbers separated by a
decimal (.) at this time.  If a value does not have a decimal, it will be encoded as
`${number}.0`.

### float

encoded as a 32-bit or 64-bit float based on the value that is provided.  the value
is prefixed by 0 or 1 to indicate whether we are dealing with a 32-bit or 64-bit value when decoding.

## Extending Types

When you provide a template to the `io` class, it will automatically read and mixin
the types that it needs to encode & decode.  This allows you to easily add new
types to the process (noting that both ends need to be aware of the given type).

The process that is followed when adding a type is as follows:

   1. Attempt to `[package require bpacket::type::${type}]` - catching any errors
   2. Confirm that a class is available `[::bpacket::type::${type}]`
   3. Add it as a mixin to our `io` class.

So adding a new type is as simple as defining it within the `::bpacket::type` namespace by its name.

All types follow the same general template.  Below is an example of the "flags"
type.  Each built-in type can be found [here](https://github.com/Dash-OS/tcl-modules/tree/master/bpacket/type).  
Always open to pull requests for improvements and additions.

```tcl
# CUSTOM BPACKET TYPE TEMPLATE

if 0 {
  @ bpacket type | $TYPE_NAME
    $TYPE_DESCRIPTION
}

# this is automatically unset once included and is simply
# used as a template for building our methods and class.
variable ::bpacket::type::current $TYPE_NAME

# register the type with its name and unique id. this is used
# when providing a template as the "type" property.
bpacket register $::bpacket::type::current $UNIQUE_TYPE_ID

if {[info command ::bpacket::type::$::bpacket::type::current] eq {}} {
  ::oo::class create ::bpacket::type::$::bpacket::type::current {
    # if we need to decode then we should bring DECODE_BUFFER into
    # scope
    # variable DECODE_BUFFER
  }
}

# this is optional and allows us to provide other types that we
# require so we know they exist.  this is called when the type  
# is first included as a mixin.
::oo::define ::bpacket::type::$::bpacket::type::current \
  method @init::$::bpacket::type::current {} {
    my requires varint boolean
  }

# how will our value be encoded?
::oo::define ::bpacket::type::$::bpacket::type::current \
  method @encode::$::bpacket::type::current {value field args} {
    set values [list]

    if {[dict exists $field args]} {
      # when args are defined, each flag has a key
      set keys [dict get $field args]
      foreach key $keys {
        if {[dict exists $value key]} {
          lappend values [dict get $value key]
        } else {
          # we keep going until a key is not present - the rest are ignored
          # this will likely throw an error in the future.
          break
        }
      }
    } else {
      # when no args are provided, each value should be a boolean
      set values $value
    }

    append encoded [my @encode::varint [llength $values]]

    foreach flag $values {
      append encoded [my @encode::boolean $flag]
    }

    return $encoded
  }

# how will our value be decoded?
::oo::define ::bpacket::type::$::bpacket::type::current \
  method @decode::$::bpacket::type::current {field args} {
    set length [my @decode::varint]

    if {[dict exists $field args]} {
      # when arguments are provided, we return a dict
      # with the re-assembled keys included again.
      set keys   [dict get $field args]
      set decoded [dict create]
    } else {
      set decoded [list]
    }

    while {$length > 0} {
      set flag [my @decode::boolean]
      # likely need to throw an error here if [llength $keys] < 1
      if {[info exists keys]} {
        set keys [lassign $keys key]
        dict set decoded $key $flag
      } else {
        lappend decoded $flag
      }
      incr length -1
    }

    return $decoded
  }
```
