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
::state::register::middleware persist ::state::middleware::persist {} {}

module create ::state::middleware::persist {
	
	# Our static configuration prop (class variable)
	::variable config {}
	# Our instance variables
  variable CONTAINER NAME QUEUE CONFIG
  
	constructor { container stateConfig middlewareConfig } {
	
	  set CONTAINER $container
	  set NAME      [namespace tail $container]
	  set config    [prop config]

	  if { $config eq {} } {
	    throw error "state-persist-middleware requires configuration"
	  }
	 
	  if { [dict exists $stateConfig persist]  } {
	    set CONFIG [dict get $stateConfig persist]
	  } elseif { [dict exists $stateConfig persist] } {
	  	set CONFIG [dict get $stateConfig persist] 
	  } else { set CONFIG {} }
	  
    if { ! [dict exists $CONFIG path] } {
      dict set CONFIG path [dict get $config path]
    }

		file mkdir [dict get $CONFIG path]
    
    if { ! [dict exists $CONFIG encrypt] } {
      if { [dict exists $stateConfig encrypt] } {
        dict set CONFIG encrypt [dict get $stateConfig encrypt] 
      } else {
        dict set CONFIG encrypt 1
      }
    }
    if { ! [dict exists $CONFIG bulk] } {
  		if { [dict exists $stateConfig bulk] } {
  			dict set CONFIG bulk [dict get $stateconfig bulk]	
  		}	else {
  			dict set CONFIG bulk 0
  		}
    }
    
	  if { ! [dict exists $CONFIG prefix] } {
	    dict set CONFIG prefix [dict get $config prefix] 
	  }
	  
	  if { ! [dict exists $CONFIG async] } {
	    if { [dict exists $config async] } {
	      dict set CONFIG async [dict get $config async] 
	    } elseif { [dict exists $stateConfig async] } {
	      dict set CONFIG async [dict get $stateConfig async]
	    } else {
	      dict set CONFIG async 1
	    }
	  }
	  
	  if { [dict get $CONFIG async] } {
		  # How long should we wait for updates before persisting to 
		  # the database?  Any updates will reset the delay and will
		  # be batched.
		  if { ! [dict exists $CONFIG delay] } {
		    if { [dict exists $config delay] } {
		      dict set CONFIG delay [dict get $config delay]
		    } else {
		      dict set CONFIG delay 5000
		    }
		  }
		  set QUEUE [dict create]
	  }
	  
	}
	
	# If out state gets destroyed, we will attempt to close the database
	destructor {
		if { [info exists QUEUE] } {
			# If our QUEUE is set we need to iterate and cancel any callbacks which
			# may currently be scheduled to occur.
			dict for {keyValue params} $QUEUE {
				catch { after cancel [dict get $params after_id] }
			}
		}
	}
	
	# The state container will call this once the state has been registered and is 
	# ready for further evaluation by the middleware.  At this time the state is 
	# prepared to be set or modified - however, it will not generate snapshots until
	# all middlewares have had a chance to run their onRegister method.
	method onRegister { schema stateConfig } {
	  if { [dict exists $stateConfig persistPath] } {
	  	set path [dict get $stateConfig persistPath]
	  } else { set path {} }
	  
	  lassign [ rehydrate $NAME $CONFIG $schema ] state reset_required
	  
	  if { $state ne {} } {
	  	# For each entry we need to try to set the state.  If an error occurs then
	  	# we need to remove the given value from the persistence
	  	set remove_entries [list]
	  	foreach entry $state {
	  		try {
	  			$CONTAINER set $entry
	  		} trap MISSING_REQUIRED {} {
	  			set reset_required 1
	  		}
	  	}
	  }
	  
	  if { $reset_required } { 
	  	after 0 [callback my RefreshPersistence]
	  	
	  }
	  
	}
	
	method RefreshPersistence {} {
		# This means that we need to refresh the persistence file from our current
		# state from scratch.  This should rarely occur - only if we switched from
		# using "bulk" to not using bulk at some point during an update.
		Remove $NAME $CONFIG
		if { [dict get $CONFIG bulk] } {
			SaveSnapshot $NAME $CONFIG bulk
		} else {
			set stateKeys [state entries $NAME]
			foreach keyValue $stateKeys {
				SaveSnapshot $NAME $CONFIG $keyValue
			}
		}
		
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
	method onSnapshot { snapshot } {
		if { [dict get $CONFIG async] } {
			set keyValue [dict get $snapshot keyValue]
			if { [dict exists $CONFIG bulk] && [dict get $CONFIG bulk] } {
			  set keyValue bulk
			}
			if { [dict exists $QUEUE $keyValue] } {
				# If $keyValue already exists in our QUEUE then we need to batch its
				# snapshot with our new snapshot, cancel the current callback, and 
				# reschedule a callback for the $DELAY period.
				after cancel [dict get $QUEUE $keyValue after_id]
			}
			set after_id [ after [dict get $CONFIG delay] [namespace code [list my ResolveAsyncSnapshot $keyValue]] ]
			dict set QUEUE $keyValue [dict create \
				after_id $after_id
			]
		} else {
			# When sychronous snapshotting is enabled, every change to the state
			# will result in the snapshot being merged into the database synchronously.
			SaveSnapshot $NAME $CONFIG $keyValue
		}
	}
	
	method ResolveAsyncSnapshot { keyValue } {
		dict unset QUEUE $keyValue
		SaveSnapshot $NAME $CONFIG $keyValue
	}
	
}


proc ::state::middleware::persist::ResolveFilename { name config {keyValue {}}} {
	if { [dict exists $config file_name] } {
    set filename [dict get $config file_name]
  } else {
    set filename [dict get $config prefix]
    if { $filename ne {} } { append filename - }
    append filename $name
  }
  if { $keyValue ne {} && ! [dict get $config bulk] && $keyValue ne "@@S" } {
  	append filename - $keyValue
  }
  return $filename
}

proc ::state::middleware::persist::Remove { name config {keyValue {}} } {
	set path     [dict get $config path]
	set filename [ResolveFilename $name $config $keyValue]
	set files    [glob -nocomplain -directory $path ${filename}*]
	if { [llength $files] } { file delete -force -- {*}$files	}
}

proc ::state::middleware::persist::SaveSnapshot { name config keyValue {new 1} } {
	set path [dict get $config path]
  set filename [ResolveFilename $name $config $keyValue]
  if { [dict get $config bulk] } {
    set value [dict values [state get $name]]
  } else {
  	if { $keyValue ne "@@S" } {
  		set value [lindex [dict values [state get $name $keyValue]] 0]	
  	} else {
  		# If we have a singleton value, we simply need to request the state
  		set value [state get $name]
  	}
  }
  if { [dict get $config encrypt] } {
    set value [::encrypt $value] 
  }
  ::fileutil::writeFile -translation binary [file join $path $filename] $value
}


# Called to rehydrate the state using the database value (if it exists). We select
# the entire table (dedicated to the state that calls it) and generate a valid "setter"
# which will set all the entries that have been saved.
proc ::state::middleware::persist::rehydrate { name config schema } {
  # Overrides all other values - we will always use the file_path
  set path [dict get $config path]
  set reset_required 0
  set was_bulk 0 ; set was_notbulk 0
  set filename [ResolveFilename $name $config]
  set files [glob -nocomplain -directory $path ${filename}*]
  if { [dict get $config bulk] } {
  	# We want to do a sanity check to determine if we matched more than a 
  	# single file.  If we did, we will reset the state by removing the files
  	if { [llength $files] > 1 || ! [file isfile [file join [file dirname [lindex $files 0]] $filename]] } {
  		set reset_required 1
  		set was_notbulk 1
  	}
  } else {
  	if { [llength $files] == 1 && [dict get $schema key] ne {} } {
  		# This may be ok, but we want to double check if we are not using bulk.
  		if { [file isfile [file join [file dirname [lindex $files 0]] $filename]] } {
  			# This means that we likely switched from "bulk" to not using bulk.	
  			set reset_required 1
  			set was_bulk 1
  		}
  	}
  }
	set contents [list]
	foreach file $files {
	  set data [::fileutil::cat -translation binary $file]
	  if { ! [string is ascii -strict $data] } {
	    # Our data appears to be encrypted
	    if { [dict exists $config encrypt] && ! [dict get $config encrypt] } {
	    	# We are encrypted but the state config changed to non-encrypted.
	    	# We need to save the unecrypted value to the file.
	  		set reset_required 1
	    }
	    set data [::decrypt $data]
	  } elseif { [dict exists $config encrypt] && [dict get $config encrypt] } {
	  	# We are now encrypted but were not before, we need to encrypt and save
	  	# it.
			set reset_required 1
	  }
	  if { ! $was_notbulk && ( [dict get $config bulk] || $was_bulk ) } {
			lappend contents {*}$data	
	  } else {
	  	lappend contents $data
	  }
	}
	if { $reset_required } {
		# This is indicated above which means that we used to have bulk persistence
		# but we don't anymore.  In this case we are going to remove the file
		# once it has been rehydrated
		foreach file $files {
			file delete -force $file
		}
	}
	return [list $contents $reset_required]
}

# Provides the global persist configuration information onto the PersistMiddleware
# instances using the "prop" command.
proc ::state::configure::persist { args } {
	namespace upvar ::state::middleware::persist config config
  dict with args {}
  
  if { ! [info exists -path] } {
		throw error "persist requires the -path argument"	
  }
  dict set config path [file normalize [file nativename [set -path]]]
  
  # Prefix value will prefix the saved state files with the given value
  if { [info exists -prefix] } {
    dict set config prefix [set -prefix] 
  } else { dict set config prefix {} }
  
  # Global async setting.  This will set the default to either synchronous
  # or asynchronous when we save our snapshots into the database.
  if { [info exists -async] } {
    dict set config async [set -async] 
  } else { dict set config async 1 }
  
  # A command to be invoked during rehydration and saving of the state
  # to allow transforming before we save it.  For example, to allow for 
  # encryption.
  if { [info exists -command] } {
  	dict set config command [set -command]
  }
  
  if { [info exists -delay] } {
		dict set config delay [set -delay]	
  } else { dict set config delay 5000 }
  
  set config $config
}