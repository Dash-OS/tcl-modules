# Contributed by PYK http://wiki.tcl.tk/28961?redir=28962
# http://wiki.tcl.tk/15566
proc extend {ens script} {
  set s {
    namespace ensemble configure %ens -unknown [list ::apply [list {ens cmd args} {
      ::if {$cmd in [::namespace eval ::${ens} {::info commands}]} {
        ::set map [::namespace ensemble configure $ens -map]
        ::dict set map $cmd ::${ens}::$cmd
        ::namespace ensemble configure $ens -map $map
      }
      ::return {} ;# back to namespace ensemble dispatch
                  ;# which will error appropriately if the cmd doesn't exist
    } [namespace current]]]
  }
  uplevel 1 [string map [list %ens [list $ens]] $s]\;[list namespace eval $ens $script]
}
