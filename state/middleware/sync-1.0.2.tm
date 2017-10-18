
# We use [task] to handle scheduling
package require task

namespace eval ::state::configure {}

# sync middleware
#
# the sync middleware is meant as a way to handle asynchronous syncing
# of the state in order to perform some kind of action.
#
# It's overall function is simple, when the state is updated - it triggers a
# delayed action.  Each time a new snapshot for the given entry is received
# we reset the delay (debounce).  Once the delay has expired we will inform the
# registered handlers to perform the sync action with the key that should
# be synced (or the entire state if bulk is set to 0)
#
# We can configure globally using
# [state configure sync -command mysync -async 0 -bulk 1 ...]
#
# This is critical when we want to perform some kind of action when the state
# changes (for example, synchronizing with a remote server).  This way we only
# make the synchronization request once the system is not only no longer modifying
# the state, but we put much less strain on both ends.
#
# Command is given $local_id $entries_modified

# Build the subscriptions middleware so that we can attach it to the state
# as needed.
::state::register::middleware sync ::state::middleware::sync {} {}

module create ::state::middleware::sync {
	# Our instance variables
  variable CONTAINER NAME CONFIG ON_SYNC SYNC_KEYS INITIAL
  # Our static configuration prop (class variable)
	::variable config {}

	constructor { container stateConfig middlewareConfig } {

	  set CONTAINER $container
	  set NAME      [namespace tail $container]
	  set config    [prop config]
	  set INITIAL   1
	  # The keys which have been modified and require syncing.
		set SYNC_KEYS [list]

	  if { [dict exists $stateConfig sync] } {
	    set CONFIG [dict get $stateConfig sync]
	  } else { set CONFIG [dict create] }

	  if { ! [dict exists $CONFIG async] } {
	  	# Default async to true if it doesnt exist as a property for sync
	    if { [dict exists $stateConfig async] } {
	      dict set CONFIG async [dict get $stateConfig async]
	    } elseif { [dict exists $config async] } {
	    	dict set CONFIG async [dict get $config async]
			} else { dict set CONFIG async 1 }
	  }

	  if { [string is true [dict get $CONFIG async]] } {
		  # How long should we wait until pushing our sync event?  Each
		  # time a change occurs the sync event will be pushed back by
		  # this amount until no changes have occurred for the delay time.
		  if { ! [dict exists $CONFIG delay] } {
		  	if { [dict exists $stateConfig delay] } {
		  		dict set CONFIG delay [dict get $stateConfig delay]
		  	} elseif { [dict exists $config delay] } {
		  		dict set CONFIG delay [dict get $config delay]
		    } else { dict set CONFIG delay 1000 }
		  }
	  } elseif { [dict exists $CONFIG delay] } {
			# no reason for this
			dict unset CONFIG delay
	  }

	  if { ! [dict exists $CONFIG batch] } {
	  	# Do we want to batch the onSync events?  This will create only
	  	# a single task rather than one per key in the state.
	  	if { [dict exists $stateConfig batch] } {
	  		dict set CONFIG batch [dict get $stateConfig batch]
	  	} elseif { [dict exists $config batch] } {
	  		dict set CONFIG batch [dict get $config batch]
	  	} else {
        dict set CONFIG batch true
      }
	  }

	  if { ! [dict exists $CONFIG bulk] } {
	  	# When bulk is set then each sync request will include the
	  	# entire state value rather than only the affected key(s).
	  	#
	  	# Note that this would be wasteful if batch is 0 as we would
	  	# need to capture the entire state every time any key changes.
			if { [dict exists $stateConfig bulk] } {
				dict set CONFIG bulk [dict get $stateConfig bulk]
			} elseif { [dict exists $config bulk] } {
				dict set CONFIG bulk [dict get $config bulk]
			}	else { dict set CONFIG bulk false }
	  }

	  if { [dict exists $CONFIG command] } {
			# The registered handler for the sync events.  This may not
			# be defined if another middleware is the one requesting syncs.
			set ON_SYNC [dict get $CONFIG command]
			dict unset CONFIG command
	  } elseif { [dict exists $config command] } {
			set ON_SYNC [dict get $config command]
	  }
	}
	destructor {
		# Cancel any tasks that we have created
		task -glob -cancel [self]*
	}
}

# The state container will call this once the state has been registered and is
# ready for further evaluation by the middleware.  At this time the state is
# prepared to be set or modified - however, it will not generate snapshots until
# all middlewares have had a chance to run their onRegister method.
#::oo::define ::state::middleware::sync method onRegister { schema stateConfig } {}
::oo::define ::state::middleware::sync method onSnapshot { snapshot } {
  # ~! "Snapshot" "State Snapshot" -context $snapshot
	set keyValue [dict get $snapshot keyValue]
	if { [dict exists $CONFIG batch] && [string is false -strict [dict get $CONFIG batch]] } {
		set resolve_id $keyValue
	} else {
    set resolve_id resolve
  }
	if { [dict exists $CONFIG bulk] && [dict get $CONFIG bulk] } {
	  set keyValue @bulk
	}
	if { $keyValue ni $SYNC_KEYS } {
    lappend SYNC_KEYS $keyValue
  }
	if { [dict get $CONFIG async] } {
		task \
			-id      @sync_state_${NAME}_$resolve_id \
			-in      [dict get $CONFIG delay] \
			-command [namespace code [list my ResolveSnapshot $resolve_id]]
	} else {
		# When sychronous snapshotting is enabled, every change to the state
		# will result in the snapshot being merged into the database synchronously.
		my ResolveSnapshot $keyValue
	}
}


# When we want to resolve a given snapshot we call this to inform the other
# middlewares that they can now parse the snapshot value
::oo::define ::state::middleware::sync method ResolveSnapshot { resolve_id } {
	task -cancel [self]_$resolve_id
	# Capture the changed keys
	if { [string is true -strict [dict get $CONFIG bulk]] } {
		# Syncing will always sync the entire state
		set sync_keys [state entries $NAME]
	} elseif { [string is false -strict [dict get $CONFIG batch]] } {
		# We arent batching, sync just this key
		set sync_keys $resolve_id
	} else {
		# Syncing will only send the modified keys
		set sync_keys $SYNC_KEYS
	}
	set SYNC_KEYS [list]
	if {[info exists ON_SYNC]} {
		catch {
      uplevel #0 [list {*}$ON_SYNC $INITIAL $NAME $sync_keys]
    }
	}
	set INITIAL 0
	# We will want to do this in the future when optimizing the middlewares
	# so that persist and others can take advantage of sync rather than
	# duplicating logic.
	#{*}$CONTAINER middleware_event sync $sync_state
}

proc ::state::configure::sync { args } {
	namespace upvar ::state::middleware::sync config config
  dict with args {}

  # Provide a default command to use for all syncs if the command is not
  # provided within the states configuration.
  if { [info exists -command] } {
    dict set config command [set -command]
  } else { dict set config command {} }

  # Global async setting.  This will set the default to either synchronous
  # or asynchronous when we save our snapshots into the database.
  if { [info exists -async] } {
    dict set config async [set -async]
    if { [string is true [set -async]] } {
	  	if { [info exists -delay] } {
				dict set config delay [set -delay]
		  }
	  }
  }

  if { [info exists -batch] } {
		dict set config batch [set -batch]
  }

  if { [info exists -bulk] } {
		dict set config bulk [set -bulk]
  }

  set config $config
}
