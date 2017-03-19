proc extend {ens script} {
  uplevel 1 [string map [list %ens [list $ens]] {
    namespace ensemble configure %ens -unknown [list ::apply [list {ens cmd args} {
      ::if {$cmd in [::namespace eval ::${ens} {::info commands}]} {
        ::set map [::namespace ensemble configure $ens -map]
        ::dict set map $cmd ::${ens}::$cmd
        ::namespace ensemble configure $ens -map $map
      }
      ::return {} ;# back to namespace ensemble dispatch
                  ;# which will error appropriately if the cmd doesn't exist
    } [namespace current]]]
  }]\;[list namespace eval $ens $script]
}
