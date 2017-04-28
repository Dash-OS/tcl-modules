# URL Encoder
# ue encode $data
# ue decode $data

package require ensembled
namespace eval ::ue { ensembled }

variable ::ue::encode_map {}
variable ::ue::decode_map {}

proc ::ue::init {} {
  ::variable encode_map
  ::variable decode_map
  ::lappend d + { }
  ::for {::set i 0} {$i < 256} {::incr i} {
    ::set c [::format %c $i]; set x %[::format %02x $i]
    ::if { ! [::string match {[a-zA-Z0-9]} $c]} {::lappend e $c $x; lappend d $x $c}
  }
  ::set encode_map $e
  ::set decode_map $d
  ::rename ::ue::init {}
}

proc ::ue::encode s {
  ::variable encode_map
  ::tailcall string map $encode_map $s
}

proc ::ue::decode s {
  ::variable decode_map
  ::tailcall string map $decode_map $s
}

::ue::init