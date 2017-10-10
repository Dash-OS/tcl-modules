####################
# State Middleware 
# 
#   The middleware mechanism provides an "extension" to the state.  These
#   middlewares are registered similar to state registration.  Once registered 
#   it may be attached to any state within the app by its name.
#
#   state register MyState {} { middlewares {logger subscriptions} ... }
#
#   Middlewares define at what point in the lifecycle they wish to be called.  In
#   most cases they will be expected to mutate values to their needs using upvar / uplevel.
####################

# snapshot 
# key integrationID set {integrationID ip state} items 
# {ip {value 192.168.1.10 prev 192.168.1.3} state {value 1 prev 0}} 
# changed {ip state} entryID 2 keys {ip state} refs 
# {entry ::Import::Modules::state::Containers::DeviceStream::Entries::2}
namespace eval ::state::configure {}

# Build the subscriptions middleware so that we can attach it to the state
# as needed.
::state::register::middleware limiter ::state::middleware::limiter {} {}

module create ::state::middleware::limiter {
	
	# Our instance variables
  variable CONTAINER NAME QUEUE CONFIG
	
	constructor { container stateConfig middlewareConfig } {
	
	  set CONTAINER $container
	  set NAME      [namespace tail $container]
		if { [dict exists $stateConfig limiter] } {
			set CONFIG [dict get $stateConfig limiter]	
		} else {
			throw error "State $NAME middleware \"limiter\" requires a configuration value but received $stateConfig"
		}
	}
	
	# If out state gets destroyed, we will attempt to close the database
	destructor {
		
	}
	
	# The state container will call this once the state has been registered and is 
	# ready for further evaluation by the middleware.  At this time the state is 
	# prepared to be set or modified - however, it will not generate snapshots until
	# all middlewares have had a chance to run their onRegister method.
	# method onRegister { schema stateConfig } {
	# 	set path {}
	  
	#   # 
	  
	# }
	
	method onRehydrated args {
		after 0 [namespace code [list my CheckLimits [dict create events 0]]]
	}
	
	# When a new snapshot is available for our state and we have defined the 
	# "onSnapshot" method, we will receive a snapshot of the modifications that
	# were made to the state.  
	#
	# There are a few ways that persistent may be handled based upon the settings
	# provided on the state.  When we have set the persist to conduct "async batch"
	# then our snapshots will be merged upon each change to the state so that we 
	# only end up evaluating and saving to the database a maximum of once per 
	# evaluation.  
	#
	# In addition, we may have a delay attached for the batching which means that
	# we will wait until a given item in the state has not been updated for $delay
	# before persisting to our database (debounce).  We will batch snapshots in the
	# meantime so we can be sure the final update will be the value of our state.
	method onSnapshot args {
		upvar 1 snapshot snapshot
		my CheckLimits
	}
	
	method CheckLimits { {local_config {}} } {
		set config [dict merge $CONFIG $local_config]
		# limiter { keys 40 sort timestamp direction ascending }
		set prev_state [state get $NAME]
		if { [dict exists $config keys] } {
			if { [dict size $prev_state] > [dict get $config keys] } {
				if { [dict exists $config by] } {
					set by [dict get $config by]	
				} else { set by values }
				if { [dict exists $config sort] } {
					set new_state [dict sort $by $prev_state {*}[dict get $config sort] -max [dict get $config keys]]	
				} else {
					set new_state [dict sort $by $prev_state -max [dict get $config keys]]
				}
				if { $new_state ne $prev_state } {
					upvar 1 snapshot snapshot
					upvar 1 READY    READY
					if { [info exists snapshot] } { unset -nocomplain snapshot }
					if { [dict exists $config events] && ! [dict get $config events] } {
						puts noevents
						{*}$CONTAINER events 0
					}
					state replace $NAME $new_state
					if { [dict exists $config events] && ! [dict get $config events] } {
						{*}$CONTAINER events 1
					}
					return 1
				}
			} 
		}
		return 0
	}

	
}


# Called to rehydrate the state using the database value (if it exists). We select
# the entire table (dedicated to the state that calls it) and generate a valid "setter"
# # which will set all the entries that have been saved.
# proc ::state::middleware::limiter::rehydrate { name config schema } {
# }