# While tuapi is what we ideally want to use, we fallback to running
# exec when tuapi is not available.
catch { package require tuapi }
package require fileutil
package require ensembled
namespace eval unix { ensembled }

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
      try {
        return [::tuapi::syscall::hostname]
      } on error {result options} { return [info hostname] }
    }
    mac - hwaddr {
      set iface [lindex $args 0]
      if { $iface eq {} } { set iface eth0 }
      set file [file join / sys class net ${iface} address]
    }
    default {
      throw error "\[unix_system\] - sysread doesnt know how to get $what $args"
    }
  }
  if { [info exists cmd] } {
    return [string trim [exec -- {*}$cmd]]
  } elseif { [info exists file] && [file isfile $file] } {
    return [string trim [::fileutil::cat $file]]
  } else {
    throw UNIX_GET_FAILURE "Failed to Read Unix System $what $args"
  }
}