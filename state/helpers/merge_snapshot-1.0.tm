# This utility is meant for the "state" package.  We take a previous and new
# snapshot and merge them together.  This is useful for "batching" snapshots
# in the case that we want to gather a final snapshot over time rather than
# evaluating every time we receive a snapshot.
#
# As items are added and removed, merge will take care of each value such as
# "created" "set" "removed" -- for example if we create an item in an entry
# then remove it, it will show up in removed and not create.  If we then 
# add it back it will flip again to give an accurate snapshot which can
# then be evaluated.
#
# Below is an example of a snapshot:
#
# keyID integrationID keyValue 83 set {integrationID state ip yay} created {} 
# changed state keys {integrationID state ip yay} removed {} 
# items {integrationID {value 83 prev 83} state {value 912183 prev 912283} 
# ip {value 192.168.83.83 prev 192.168.83.83} yay {value 1 prev 1}} 
# refs {entry ::tcm::module::state::Containers::MyState2::Entries::83}
#
proc ::state::merge_snapshot { prev new } {
	puts merge
  dict with prev {}
	set items [dict merge $items [dict get $new items]]
	foreach e [dict get $new removed] { 
		set keys    [lsearch -all -inline -not -exact $keys    $e]
		set set     [lsearch -all -inline -not -exact $set     $e]
		set changed [lsearch -all -inline -not -exact $changed $e]
		set created [lsearch -all -inline -not -exact $created $e]
		lappend removed $e
		dict unset items $e
	}
	foreach e [dict get $new created] { 
		lappend keys    $e
		lappend created $e
		set removed [lsearch -all -inline -not -exact $removed $e]
		dict set items $e [dict get $new items $e]
	}
	foreach e [dict get $new set] {
		if { $e ni $set } { lappend set $e }
	}
	foreach e [dict get $new changed] {
		if { $e ni $changed } { lappend changed $e }
	}
	return [dict merge $prev $new [dict create \
		keys $keys set $set changed $changed \
		created $created items $items removed $removed
	]]
}

# Coro Optimization for Merge - Unfinished
# proc merger { snapshot } {
# 	dict with snapshot {}
# 	if { ! [string match [namespace current]* [info coroutine] ] } {
# 	  namespace eval coros {}
# 	  set id [string cat [dict get $snapshot localID]]
# 	  # TO DO - FINISH THIS
# 	  tailcall [namespace current]::coros::
# 	}
# 	yield [info coroutine]
# 	while 1 {
# 	  set new [yield]
# 	  set items [dict merge $items [dict get $new items]]
#   	foreach e [dict get $new removed] { 
#   		set keys    [lsearch -all -inline -not -exact $keys    $e]
#   		set set     [lsearch -all -inline -not -exact $set     $e]
#   		set changed [lsearch -all -inline -not -exact $changed $e]
#   		set created [lsearch -all -inline -not -exact $created $e]
#   		lappend removed $e
#   		dict unset items $e
#   	}
#   	foreach e [dict get $new created] { 
#   		lappend keys    $e
#   		lappend created $e
#   		set removed [lsearch -all -inline -not -exact $removed $e]
#   		dict set items $e [dict get $new items $e]
#   	}
#   	foreach e [dict get $new set] {
#   		if { $e ni $set } { lappend set $e }
#   	}
#   	foreach e [dict get $new changed] {
#   		if { $e ni $changed } { lappend changed $e }
#   	}
#   	return [dict merge $prev $new [dict create \
#   		keys $keys set $set changed $changed \
#   		created $created items $items removed $removed
#   	]]
# 	}
# }