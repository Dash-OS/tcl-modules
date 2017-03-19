# package require cmdlist
# simple way of building scripts that are mixed with local and remote 
# variable context.
# useful when doing things in situations like uplevel
# uplevel 1 [cmdlist [list puts $localvar] {set $remotevar}]
proc cmdlist args { format [string repeat {%s;} [llength $args]] {*}$args }