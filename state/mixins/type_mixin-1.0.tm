::oo::class create ::state::mixins::typed {
	method validate {name {withtype {}} {response 1}} {
		my variable PARAMS
		
		if { $withtype eq {} } {
			my variable TYPE
		} else { set TYPE $withtype }
		
		if { [info exists TYPE] && $TYPE ne {} } {
			
			upvar 1 $name value
			
			if { [info exists PARAMS] && $PARAMS ne {} } {
				set args [list $value $PARAMS]		
			} else { set args [list $value] }
			
			set TypeSchema [::state::type $TYPE]
			
			if { [dict exists $TypeSchema pre] } {
				set value [{*}[dict get $TypeSchema pre func] {*}$args]
			}
			
			if { [dict exists $TypeSchema validate] } {
				set response [{*}[dict get $TypeSchema validate func] {*}$args]
			}
			
			if { [dict exists $TypeSchema post] } {
				set value [{*}[dict get $TypeSchema post func] {*}$args]
			}
			
		} elseif { ! [info exists TYPE] } {
			throw error "You must specify the TYPE variable before validating!"
		}

		
		return $response
	}
	
	method serialize {json key op value args} {
		my variable TYPE
		if { [info exists TYPE] && $TYPE ne {} } {
			set TypeSchema [::state::type $TYPE]
			if { [dict exists $TypeSchema json] } {
				switch -nocase -- $op {
					snapshot {
						# We have both prev and current values
						if { [dict get $value prev] eq {} } {
							# We dont serialize empty values
							dict unset value prev
						}
						$json map_key $key map_open
						dict for { k v } $value {
							{*}[dict get $TypeSchema json func] $k $v $json
						}
						$json map_close
					}
					prev - values {
						if { $value ne {} } {
							tailcall {*}[dict get $TypeSchema json func] $key $value $json	
						}
						
					}
				}
			}
		}
	}
}
