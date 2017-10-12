namespace eval ::bpacket {}

set ::bpacket::value_types [dict create \
  vint      0 \
  string    2 \
  bool      15 \
  flags     16 \
  list      17 \
  dict      18 \
  container 19 \
  raw       20 \
  aes       21
]

set ::bpacket::value_ids [dict create \
   0 vint \
   2 string \
  15 bool \
  16 flags \
  17 list \
  18 dict \
  19 container \
  20 raw \
  21 aes
]

::oo::class create ::bpacket::writer {}

::oo::define ::bpacket::writer {
  variable PACKET FIELDS TEMPLATE
}

::oo::define ::bpacket::writer constructor args {
  set PACKET   {}
  set FIELDS   {}
  set TEMPLATE {}
}

# append to the packet
::oo::define ::bpacket::writer method append args { append PACKET {*}$args }

::oo::define ::bpacket::writer method set value {
  set PACKET $value
}

::oo::define ::bpacket::writer method reset {} {
  set PACKET {}
  set FIELDS {}
}

# retrieve the current packet, providing the overall
# encapsulation for the packet.
#
# \xC0\x8D$length$PACKET\x00
::oo::define ::bpacket::writer method get {} {
  # puts "Length  [my length]"
  # puts "\n\n\n"
  return [format \
    {%s%s%s%s} \
    \xC0\x8D \
    [my uint64 [my length]] \
    $PACKET \
    \x00
  ]
}

::oo::define ::bpacket::writer method fields {} { return $FIELDS }

# get the length of the packet currently
::oo::define ::bpacket::writer method length {} { string length $PACKET }

# get the bytelength of the packet
::oo::define ::bpacket::writer method bytelength {} { string bytelength $PACKET }

# add $n null padding to the packet \x00 0x00 NULL
::oo::define ::bpacket::writer method pad { {n 1} } { return [binary format x$n] }

# append a binary encoded bool \x00 \x01 to our packet
::oo::define ::bpacket::writer method bool { bool } {
  if { [string is true -strict $bool] } {
    return [binary format c 1]
  } else {
    return [binary format c 0]
  }
}

::oo::define ::bpacket::writer method build { data } {
  if { $TEMPLATE eq {} } { throw error "Building required template" }
  lassign $TEMPLATE schema map required
  dict for {k v} $data {
    if { [dict exists $map $k] } {
      lassign [dict get $map $k] value_type required params
      set field_id $k
    } elseif { [dict exists $schema $k] } {

    } else {
      throw error "Encoding Failed: $k is not a known field"
    }
    my append [ my field $field_id $value_type $v ]
  }
  return [my get]
}

::oo::define ::bpacket::writer method template { template } {
  set schema [dict create] ; set map [dict create] ; set required [list]
  foreach line [split $template \n] {
    set line [string trim $line]
    if { $line eq {} } { continue }
    lassign [split $line |] params field_id args
    set field_id [string trim $field_id]
    if { "*" in $params } {
      set req 1
      lappend required $field_id
      set params [lsearch -all -inline -not -exact $params "*"]
    } else { set req 0 }
    set keys [lassign $params value_type]
    if { [dict exists $::bpacket::value_types $value_type] } {
      set value_type [dict get $::bpacket::value_types $value_type]
    }
    set params [list $value_type $req $keys]
    if {$args ne {}} {
      set args [list {*}$args]
      lappend params $args
    }
    foreach key $keys {
      dict set schema $key [dict create id $field_id type $value_type]
      if { $req } { dict set schema $key required $req }
      if {$args ne {}} {
        dict set schema $key args $args
      }
    }
    dict set map $field_id $params
  }
  set TEMPLATE [list $schema $map $required]
  return $TEMPLATE
}

# append a uint64 value to our packet
::oo::define ::bpacket::writer method uint64 { byte } {
  if {$byte < 128} {  ;# 2**7
    append x [binary format c $byte]
    return $x
  } elseif {$byte < 16384} {  ;# 2**14
    append x [binary format c [expr {($byte & 127) | 128}]]
    append x [binary format c [expr {$byte >> 7}]]
    return $x
  } elseif {$byte < 2097152} {  ;# 2**21
    append x [binary format c [expr {($byte & 127) | 128}]]
    append x [binary format c [expr {(($byte >> 7) & 127) | 128}]]
    append x [binary format c [expr {$byte >> 14}]]
    return $x
  }
  set n 0; set sh 0
  while 1 {
    set b [expr {($byte >> $sh) & 127}]
    incr sh 7; incr n
    if {$byte >> $sh} {
      append x [binary format c [expr {$b | 128}]]
    } else {
      append x [binary format c $b]
      return $x
    }
  }
  return $x
}

# add a string which is prefixed by the strings length via varint
::oo::define ::bpacket::writer method string { string } {
  set string [encoding convertto utf-8 $string]
  set length [string length $string]
  append response [my uint64 $length] $string
}

# add raw bytes to our packet which is not converted to utf-8 first
::oo::define ::bpacket::writer method bytes { bytes } {
  append response [my uint64 [string length $bytes]] $bytes
}

::oo::define ::bpacket::writer method flag { n1 n2 } {
  #return [ my uint64 [expr {($n1 << 3) | $n2}] ]
}

::oo::define ::bpacket::writer method field { field_num wire_type args } {
  # We deviate from protocol buffers here to allow any wire_type
  #puts "Field $field_num type $wire_type | $args"
  append tag [my uint64 $field_num] [my uint64 $wire_type]
  # TODO: Handle fields with the same value
  dict set FIELDS $field_num tag $tag
  if {$args ne {}} {
    switch -- $wire_type {
      0 { # Varint
        set args [lindex $args 0]
        if { ! [string is entier -strict $args] } {
          throw error "varint must be entier value but got: $args"
        }
        set value [my uint64 [lindex $args 0]]
      }
      1 {

      }
      2 { # Length-Delimited Data
        set value [my string [lindex $args 0]]
      }
      15 { # Boolean
        set value [my bool [lindex $args 0]]
      }
      16 {
        # Flags - A list of varints prefixed by the list length.
        if {[llength $args] == 1} {
          set args [lindex $args 0]
        }
        set values [my uint64 [llength $args]]
        foreach n $args {
          lappend values [ my uint64 $n ]
        }
        set value [join $values {}]
      }
      17 - 18 {
              # 17 - List - A field of values separated by \x00 and prefixed by length
              # 18 - Keyed Dictionary - $varint $value - where $varint is key
              #      This works similar to list except it is converted to a
              #      dictionary on the other end based on the given keys.
        if { [llength $args] == 1 } {
          set args [lindex $args 0]
        }
        set values [my uint64 [llength $args]]
        foreach e $args {
          lappend values [my string $e]
        }
        set value [join $values {}]
      }
      19 { # Container - a container simply wraps values in a length-delimited
           #             fashion.
      }
      20 { # raw - Simply add the values to the packet
        set value [my bytes [lindex $args 0]]
      }
      21 { # AES Encrypted with pre-shared key
          # TODO: Possibly encrypt the data using a configured
          #       encryption key.
        set value [my bytes [lindex $args 0]]
      }
    }
    dict set FIELDS $field_num value $value
  } else {
    set value {}
  }
  if { $value ne {} } {
    return [format {%s%s} $tag $value]
  } else {
    return $tag
  }
}

# convert packet to hex
::oo::define ::bpacket::writer method hex { {h H} } {
  binary scan $PACKET $h* hex
  return $hex
}
