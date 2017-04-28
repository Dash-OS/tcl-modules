package require fileutil
package require ensembled
package require json_tools
package require ip_tools

namespace eval ::unix {}
namespace eval ::unix::serialize { ensembled }

# {"cpu":[1132615,0,2401999,28616318,13,4775,24818,0,0,0],
# "cpu0":[1132615,0,2401999,28616318,13,4775,24818,0,0,0],"ctxt":1211610385,
# "btime":1481418495,"processes":2999236,"procs_running":2,"procs_blocked":0,
# "softirq":[58776092,0,10831297,2994611,6909044,434,0,4432284,0,1255,33607167]}
proc ::unix::serialize::procstat args {
  set rawCPU   [ ::fileutil::cat /proc/stat ]
  set lines    [ split $rawCPU \n ]
  set tempDict {{}}
  foreach line $lines {
    switch -glob -- $line {
      0* { continue }
      cpu* {
        set stats [lassign $line cpu]
        json set tempDict $cpu [json typed $stats]
      }
      ctxt* {
        set stats [lassign $line ctxt]
        json set tempDict $ctxt [json typed $stats]
      }
      btime* {
        set stats [lassign $line btime]
        json set tempDict $btime [json typed $stats]
      }
      process* {
        set stats [lassign $line processes]
        json set tempDict $processes [json typed $stats]
      }
      procs_r* {
        set stats [lassign $line procs_running]
        json set tempDict $procs_running [json typed $stats]
      }
      procs_b* {
        set stats [lassign $line procs_blocked]
        json set tempDict $procs_blocked [json typed $stats]
      }
      softirq* {
        set stats [lassign $line softirq]
        json set tempDict $softirq [json typed $stats]
      }
    }
  }
  return $tempDict
}

proc ::unix::serialize::meminfo args {
  set _meminfo [ string tolower [::fileutil::cat /proc/meminfo] ]
  set _meminfo [ dict create {*}[ string map { "kb" "" ":" "" } ${_meminfo} ] ]
  if { $args ne {} } { set _meminfo [dict pull meminfo {*}$args] }
  return [json typed ${_meminfo}]
}

proc ::unix::serialize::uptime args { 
  set json {{}}
  lassign [ ::fileutil::cat /proc/uptime ] uptime idle
  json set json uptime [json typed $uptime]
  json set json idle   [json typed $idle]
  return $json
}

proc ::unix::serialize::loadavg args {
  set json {{}}
  set loadAvg [ ::fileutil::cat /proc/loadavg ]
  lassign $loadAvg 1 5 15 kernel lastPID
  json set json 1  [json typed $1]
  json set json 5  [json typed $5]
  json set json 15 [json typed $15]
  return $json
}

proc ::unix::serialize::process_files {pid {files {}}} {
  set fds [ glob -nocomplain -directory /proc/${pid}/fd * ]
  foreach fd $fds { lappend files [file readlink $fd] }
  return [json object create \
    total [llength $fds] \
    files $files
  ]
}

proc ::unix::serialize::ifconfig { {iface eth0} } {
  return [json typed [dict create {*}[::tuapi::syscall::ifconfig $iface]]]
}

proc ::unix::serialize::stat_serializer path {
  set netstat [ ::fileutil::cat $path ]
  set lines [split $netstat \n]
  set tempDict {{}}
  foreach line $lines {
    set stats [lassign $line key]
    set key   [string map {":" ""} $key]
    if { $key eq {} || $stats eq {} } { continue }
    if { [json exists $tempDict $key] } {
      foreach k $keys s $stats {
        json set tempDict $key $k [json typed $s]
      }
    } else {
      json set tempDict $key {{}}
      set  keys $stats
    }
  }
  return $tempDict
}

proc ::unix::serialize::route { {iface eth0} } {
	set data      [unix get route]
	set lines     [lrange [split $data \n] 1 end]
	set tempDict  {}
	foreach line $lines {
		set gatewayIP     {}
	  set netMask       {} 
	  set destinationIP {}
		lassign $line iface dest gateway flags refcnt use metric mask mtu window irtt
		# We need to do this so the reprentation is a pure string
		append gatewayIP     [ip hex2dec $gateway]
		append netMask       [ip hex2dec $mask]
		append destinationIP [ip hex2dec $dest]
		if {$gateway ne "00000000"} { dict set tempDict $iface gatewayIP     $gatewayIP      }
		if {$mask    ne "00000000"} { dict set tempDict $iface netMask       $netMask        }
		if {$dest    ne "00000000"} { dict set tempDict $iface destinationIP $destinationIP  }
	}
	if { [dict exists $tempDict $iface] } {
	  return [json typed [dict get $tempDict $iface]]
	}
}

proc ::unix::serialize::netstat {} { tailcall [namespace current]::stat_serializer /proc/net/netstat }
proc ::unix::serialize::snmp {} { tailcall [namespace current]::stat_serializer /proc/net/snmp }


proc ::unix::serialize::netdev {} {
  set dev   [::fileutil::cat /proc/net/dev]
  set lines [lrange [split $dev \n] 1 end]
  set stats [lassign $lines keys]
  set keys  [split $keys |]
  set tempDict {}
  lassign $keys -> rxKeys txKeys
  foreach interface [string trim $stats] {
    set stats [lassign $interface iface]
    set iface [string map {":" ""} $iface]
    if { $iface eq {} || $stats eq {} } { continue }
    foreach rxStat $rxKeys {
      set stats [lassign $stats stat]
      dict set tempDict $iface rx $rxStat $stat
    }
    foreach txStat $txKeys {
      set stats [lassign $stats stat]
      dict set tempDict $iface tx $txStat $stat
    }
  }
  return $tempDict
}

proc ::unix::serialize::processes args {
  try {
    set processes [ unix get ps ]
    set lines [split $processes \n]
    set lines [lrange $lines 1 end]
    foreach line $lines {
      set line [string map {{<} {} {>} {} {*} {}} $line]
      set pid  [lindex $line 0]
      set user [lindex $line 1]
      set virtualSize [lindex $line 2]
      if {[string match "*m" $virtualSize]} {
        set virtualSize [string map {"m" ""} $virtualSize]
        set virtualSize [expr {$virtualSize * 1000}]
      }
      set stat [lindex $line 3]
      set name [lrange $line 4 end]
    }
  } on error { result options } {
    ::onError $result $options "While getting System Processes"
  }
}

