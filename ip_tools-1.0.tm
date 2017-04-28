package require ensembled

namespace eval ::ip { ensembled }

proc ::ip::normalize ip {
  set r [scan $ip %d.%d.%d.%d%c o1 o2 o3 o4 trash]
  if {$r == 4} { append normalized $o1 . $o2 . $o3 . $o4 } else { return }
  return $normalized
}

proc ::ip::hex2dec {hex {reverse 1}} {
  set ip [scan $hex %2x%2x%2x%2x]
  if { $reverse } { set ip [lreverse $ip] }
  set ip [join $ip .]
  set ip [regexp -inline -all {\d+\.\d+\.\d+\.\d+} $ip]
  return [string cat "$ip"]
}

