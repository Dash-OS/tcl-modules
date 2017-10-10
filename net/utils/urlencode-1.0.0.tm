# URL Encoder
# ue encode $data
# ue decode $data
namespace eval ::net {}

variable ::net::encode_map {}
variable ::net::decode_map {}

# removes itself once completed.
proc ::net::ueinit {} {
  ::lappend d + { }
  ::for {::set i 0} {$i < 256} {::incr i} {
    ::set c [::format %c $i]
    ::set x %[::format %02x $i]
    ::if { ! [::string match {[a-zA-Z0-9]} $c] } {
      ::lappend e $c $x
      ::lappend d $x $c
    }
  }
  ::set ::net::encode_map $e
  ::set ::net::decode_map $d
  ::rename ::ue::init {}
}

proc ::net::urlencode s {
  ::tailcall ::string map $::net::encode_map $s
}

proc ::net::urldecode s {
  ::tailcall ::string map $::net::decode_map $s
}

::net::ueinit
