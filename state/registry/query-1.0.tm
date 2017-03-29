namespace eval ::state {}
namespace eval ::state::register {}
namespace eval ::state::register::registry {}
variable ::state::register::registry::registry  [dict create]
variable ::state::register::registry::modifiers [list]
variable ::state::register::registry::active    [list]
variable ::state::register::registry::queries   [dict create]

# At registration, convert to proper internal representations
# so we can avoid shimmering at evaluation time.
proc ::state::register::query { query schema } {
	if { $query in [dict keys $registry::queries] } {
		throw error "\[tcl_query_parts\] - $query is already registered.  You may not register a query twice at this time."	
	}
	dict set registry::queries $query $query
	dict for { op value } $schema {
		switch -- $op {
			alias    { 
				set aliases [list {*}$value] 
				dict set registry::registry $query $op $aliases
				foreach alias $aliases { dict set registry::queries $alias $query }
			}
			evaluate { dict set registry::registry $query $op [string trim $value] }
			active   {
				dict set registry::registry $query $op $value
				if { [string is true -strict $value] } {
					set isActive 1
					lappend registry::active $query
				}
			}
			default  { dict set registry::registry $query $op $value }
		}
	}
	if { [info exists isActive] && [dict exists $registry::registry $query alias] } {
		lappend registry::active {*}[dict get $registry::registry $query alias]	
	}
}

proc ::state::register::modifier { modifier schema } {
	dict set registry::modifiers $modifier [string trim $schema]
}

proc ::state::query { query } {
	return [dict get $register::registry::registry $query]
}

proc ::state::queries {} {
	return $register::registry::queries
}

proc ::state::modifiers {} {
	return $register::registry::modifiers
}

proc ::state::active {} {
	return $register::registry::active
}

proc ::state::query_schema { query } {
	return [dict get $register::registry::registry [register::resolve_query $query]]
}

proc ::state::register::resolve_query query {
	return [dict get $registry::queries $query]
}

proc ::state::register_default_queries {} {
	::state::register::query set [dict create \
		active   1 \
		alias    [list "modified"] \
		evaluate { expr { $key eq "*" || $key in $set } }
	]
	::state::register::query exists [dict create \
		alias [list "defined"] \
		evaluate { expr { $key in $keys } }
	]
	::state::register::query existed [dict create \
		evaluate { expr { ( $key ni $created ) && ( $key in $keys ) } }
	]
	::state::register::query changed [dict create \
		active 1 \
		alias [list "changes"] \
		evaluate { expr { $changed ne {} && ( $key eq "*" || $value != $prev ) } }
	]
	::state::register::query created [dict create \
		active 1 \
		alias [list "added"] \
		evaluate { expr { $created ne {} && ( $key eq "*" || $key in $created ) } }
	]
	::state::register::query removed [dict create \
		active 1 \
		alias [list "deleted"] \
		evaluate { expr { $removed ne {} && ( $key eq "*" || $key in $removed ) } }
	]
	::state::register::query = [dict create \
		alias [list "eq" "==" "equal"] \
		evaluate { expr { $value == $params } }
	]
	::state::register::query != [dict create \
		alias [list "ne" "not equal"] \
		evaluate { expr { $value != $params } }
	]
	::state::register::query >= [dict create \
		alias [list "greater equal" "ge"] \
		evaluate { expr { $value >= $params } }
	]
	::state::register::query > [dict create \
		alias [list "greater than" "gt"] \
		evaluate { expr { $value > $params } }
	]
	::state::register::query < [dict create \
		alias [list "less than" "lt"] \
		evaluate { expr { $value < $params } }
	]
	::state::register::query <= [dict create \
		alias [list "less equal" "le"] \
		evaluate { expr { $value <= $params } }
	]   
	::state::register::query >_ [dict create \
		active 1 \
		alias [list "rises above"] \
		evaluate { expr { $value > $params && $prev <= $params } }
	] 
	::state::register::query _< [dict create \
		active 1 \
		alias [list "falls below"] \
		evaluate { expr { $value < $params && $prev >= $params } }
	]   
	::state::register::query % [dict create \
		alias [list "divisible by"] \
		evaluate { expr { ( $value % $params ) == 0 } }
	]
	::state::register::query in [dict create \
		alias [list "is in"] \
		evaluate { expr { $value in $params } }
	]
	::state::register::query ni [dict create \
		alias [list "not in"] \
		evaluate { expr { $value ni $params } }
	]
	::state::register::query match [dict create \
		evaluate {
			if {"-nocase" in $params} {
				set params [string trim [string map {"-nocase" ""} $params]]
				lappend args -nocase
			} else { set args {} }
			string match {*}$args $params $value
		}
	]
	::state::register::query regexp [dict create \
		evaluate {
			set line $value
			regexp [subst {*}$paramss]
		}
	]
	::state::register::query include [dict create \
		evaluate {
			if {"-nocase" in $params} {
				set params [string trim [string map {"-nocase" ""} $params]]
				lappend args -nocase
			} else { set args {} }
			string match {*}$args *${params}* $value
		}
	]
	::state::register::query notInclude [dict create \
		evaluate {
			if {"-nocase" in $params} {
				set params [string trim [string map {"-nocase" ""} $params]]
				lappend args -nocase
			} else { set args {} }
			expr { ! [string match {*}$args *${params}* $value] }
		}
	]
	::state::register::query startsWith [dict create \
		alias [list "starts with"] \
		evaluate { string match ${params}* $value }
	]
	::state::register::query endsWith [dict create \
		alias [list "ends with"] \
		evaluate { string match *$params $value }
	]
	::state::register::query command [dict create \
		alias    [list "eval"] \
		evaluate { uplevel #0 [list {*}$params $value] }
	]
	::state::register::query isType [dict create \
	  evaluate { string is $params -strict $value }
	]
	
	# Register Default Modifiers
	::state::register::modifier set {}
	::state::register::modifier removed {}
	::state::register::modifier is {}
	::state::register::modifier was {
		on before-eval
		evaluate { set value $prev }
	}
	::state::register::modifier becomes {
		on after-eval 
		evaluate {
			if { [string is true -strict $result] } {
				set value $prev
				set result [expr { ! [try $evaluate] }]
			}
		}
	}
	::state::register::modifier not {
		on after-eval 
		evaluate { set result [ string is false -strict $result ] }
	}

	rename ::state::register_default_queries {}
}

::state::register_default_queries