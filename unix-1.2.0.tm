# While tuapi is what we ideally want to use, we fallback to running
# exec when tuapi is not available.
#
# 10/14 - use tuapi to discover iface if needed
#
catch { package require tuapi }

package require fileutil
package require ensembled

namespace eval unix { ensembled }

if 0 {
  @ unix platform
    | Simplified platform handling by parsing and returning
    | a simple enumeration based on the os/platform.
  @returns {?osx|linux?}
}
proc ::unix::platform {} {
  switch -- $::tcl_platform(platform) {
    unix {
      switch -nocase -- $::tcl_platform(os) {
        darwin {
          return osx
        }
        linux - default {
          return linux
        }
      }
    }
    default {
      # This is not a unix platform
      return
    }
  }
}

if 0 {
  @ unix restart
    | Restart the system using the [shutdown -r now] command
  @arg delay {entier}
    An argument giving a ms delay before conducting the restart.
    Defaults to 5000 ms.
}
proc ::unix::restart { {delay 5000} } {
  after $delay {
    if { [catch { ::tuapi::syscall::reboot }] } {
      try {
        exec -- shutdown -r now
      } on error {result options} {
        puts stderr $result
      }
    }
  }
}

if 0 {
  @ unix get
    | Capture various data from the unix system.  Generally returns
    | raw data that should then be parsed and handled as needed.
  @arg what {ps|route|load|mem|uptime|mount|arp|fdisk|nameservers|stat|hostname|mac}
  @args {mixed}
    additional arguments to provide the requested command when
    specified.
  @returns {mixed}
}
proc ::unix::get { what args } {
  switch -nocase -glob -- $what {
    ps     { set cmd [list ps {*}$args] }
    route  { set file /proc/net/route }
    load*  { set file /proc/loadavg }
    mem*   { set file /proc/meminfo }
    upt*   { set file /proc/uptime  }
    mount* { set file /proc/mounts  }
    arp    { set file /proc/net/arp }
    fdisk  { set cmd [list fdisk -l {*}$args] }
    ns - nameserv* { set file /etc/resolve.conf }
    stat - procst* { set file /proc/stat }
    hostname - host* {
      switch -- [unix platform] {
        osx {
          return [info hostname]
        }
        linux {
          try {
            return [::tuapi::syscall::hostname]
          } on error {result options} { return [info hostname] }
        }
      }
    }
    mac - hwaddr {
      switch -- [unix platform] {
        osx {
          lassign $args iface
          if { $iface eq {} } { set iface en0 }
          set cmd [list ifconfig $iface | awk "/ether/{print \$2}"]
        }
        linux {
          lassign $args iface
          if {![catch {package require tuapi}]} {
            if {$iface eq {}} {
              set ifaces [::tuapi::syscall::ifconfig]
              set ifaces [lsearch -inline -all -not -exact $ifaces lo]
              set iface  [lindex $ifaces 0]
            }
            return [dict get [::tuapi::syscall::ifconfig $iface] hwaddr]
          } else {
            if { $iface eq {} } { set iface eth0 }
            set file [file join / sys class net ${iface} address]
          }

        }
      }
    }
    default {
      throw UNIX_GET_DEFAULT "\[unix_system\] - sysread doesnt know how to get $what $args"
    }
  }
  if { [info exists cmd] } {
    return [string trim [exec -ignorestderr -- {*}$cmd]]
  } elseif { [info exists file] && [file isfile $file] } {
    return [string trim [::fileutil::cat $file]]
  } else {
    throw UNIX_GET_FAILURE "Failed to Read Unix System $what $args"
  }
}
