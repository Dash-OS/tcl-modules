# bpacket (binary packet)

> Documentation is a work in progress

`[bpacket]` is a package that makes encoding & decoding compact binary packets to transmit your data on the wire or other bandwidth-sensitive situations.  It attempts to pack information as tightly as possible for transmission in many-to-many communication protocols like [tcl-cluster](https://github.com/Dash-OS/tcl-cluster).

## Binary Template

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


### list

lists are encoded as a length-delimited list of "strings" which match `$varint (llength) ...$varint (value length) $value (any) \x00...]`

### container

containers simply wrap a group of values.  it is encoded as `$varint $values`

### raw

raw values are not encoded and are added as their raw bytes to the packet.  they are provided as `$varint $bytes`
