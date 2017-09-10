# bpacket (binary packet)

> Documentation is a work in progress

`[bpacket]` was built to provide a compact binary wire protocol.  It attempts to pack information as tightly as possible for transmission in many-to-many communication protocols like [tcl-cluster](https://github.com/Dash-OS/tcl-cluster).

## Binary Template

Before we can encode/decode packets that `bpacket` will create for us, we need to provide it with a template which it will use.  This allows us to optimize and customize our packets to our specific use-case.

> **Note:** As of writing this readme, asterix (required) values is not enforced by the package.  For now they will simply be ignored, however we do plan to add such enforcement in future version(s).

bpacket supports various value types.  The template allows us to define
how we will provide each value and how they will be formed.  At this time all values are completely optional.  

> **Tip:** Values can be encoded/decoded in any order

|  Type  |  Description  |
| :----------: |:----------- |
| vint | a [varint](https://developers.google.com/protocol-buffers/docs/encoding#varints)-like value which packs entier values as tightly as possible. |
| string | a utf-8 encoded string value |
| bool | a boolean value |
| flags | a list of varints prefixed by the list length |
| list | a list of strings |
| dict | a key/value pairing of values where only the values are encoded, the keys are constructed when decoding |
| container | containers can be thought of as namespaces within our packets.  They allow us to continue formatting values in a nested manner, but to provide a namespace to a given group of values. |
| raw | a raw length-delimited value (no encoding or modification) |
| aes | _Future_ aes encryption of value with provided key |

```tcl
package require bpacket

set encoder [::bpacket::writer new]

$encoder template {
  * flags  type channel   | 1
  * string hid            | 2
  * string sid            | 3
    flags  known f2 f3 f4 | 4
    vint   timestamp      | 5
  * list   protocols      | 6
    string ruid           | 7
    string op             | 8
    string data           | 9
    aes    raw            | 10
    list   tags           | 11
    bool   keepalive      | 12
    list   filter         | 13
    string error          | 14
}
```

## Decoding Packets

Decoding our protocol is done by creating a "reader" object.  We can then iterate through the given packet until completed. Each time we call `[$reader next]` it will return a list with our data.

We will need to be aware of our template to understand how to parse the
data properly.  

Our reader is capable of handling multiple packets appended in the case that we receive more than one packet in a transmission (for example, when using udp protocol for transmission).

> **Note:** Our longer term plan is to use the template value to automatically parse the given data.  There are a few details in our specific use-cases that make this difficult to do while allowing us to maintain absolutely efficiency during parsing.

```tcl
package require bpacket

proc decode { packet {cluster {}} } {
  set result [dict create]
  set results [list]
  try {
    set reader [::bpacket::reader new $packet]
    set active 1
    while {$active} {
      lassign [$reader next] active id type data
      switch -- $active {
        0 {
          # We are done parsing the packet(s)!
          lappend results $result
          break
        }
        1 {
            # We have more to parse!
            switch -- $id {
              1  {
                lassign $data datatype channel
                dict set result type $datatype
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
              13 { dict set result filter $data }
              14 { dict set result error $data }
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
    #puts stderr "Malformed Packet! $result"
    catch { $reader destroy }
  }
  if { $active } { set result {} }
  return $results
}
```

## Encoding Notes

### vint

> Each byte in a varint, except the last byte, has the most significant bit (msb) set – this indicates that there are further bytes to come. The lower 7 bits of each byte are used to store the two's complement representation of the number in groups of 7 bits, least significant group first.
[...read more about varints](https://developers.google.com/protocol-buffers/docs/encoding#varints)

### flags

also can be thought of as a "list of entiers", this is a length-delimited list of numbers following the pattern `$varint (llength) ...$varint (flag)...`

### list

lists are encoded as a length-delimited list of "strings" which match `$varint (llength) ...$varint (value length) $value (any) \x00...]`

### container

containers simply wrap a group of values.  it is encoded as `$varint $values`

### raw

raw values are not encoded and are added as their raw bytes to the packet.  they are provided as `$varint $bytes`
