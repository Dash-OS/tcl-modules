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
package require sqlite3
package require oo::module
package require state::helpers::merge_snapshot

# Build the subscriptions middleware so that we can attach it to the state
# as needed.
::state::register::middleware sqlite_persist ::state::middleware::sqlite_persist {} {}

namespace eval db {}

module create ::state::middleware::sqlite_persist {
	
	# Our static configuration prop (class variable)
	::variable config {}
	# Our instance variables
  variable CONTAINER ASYNC DB NAME QUEUE DELAY
  
	constructor { container stateConfig middlewareConfig } {
	
	  set CONTAINER $container
	  set NAME      [namespace tail $container]
	  set config    [prop config]
	  
	  if { $config eq {} } {
	    puts "\n You must configure the Persist Middleware before using it"
	    puts "import ConfigurePersist from \"state-persist-middleware\""
	    puts "ConfigurePersist static configure \$config"
	    throw error "state-persist-middleware requires configuration"
	  }
	  
	  if { [dict exists $stateConfig persistAsync] } {
	    set ASYNC [dict get $stateConfig persistAsync] 
	  } elseif { [dict exists $config async] } {
	    set ASYNC [dict get $config async] 
	  } else { set ASYNC 1 }
	  
	  if { $ASYNC } {
		  # How long should we wait for updates before persisting to 
		  # the database?  Any updates will reset the delay and will
		  # be batched.
	  	if { [dict exists $stateConfig persistDelay] } {
		  	set DELAY [dict get $stateConfig persistDelay]	
		  } elseif { [dict exists $config delay] } {
				set DELAY [dict get $config delay]	
		  } else { set DELAY 0 }	
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
		static close $NAME
	}
	
	# The state container will call this once the state has been registered and is 
	# ready for further evaluation by the middleware.  At this time the state is 
	# prepared to be set or modified - however, it will not generate snapshots until
	# all middlewares have had a chance to run their onRegister method.
	method onRegister { schema stateConfig } {
	  if { [dict exists $stateConfig persistPath] } {
	  	set path [dict get $stateConfig persistPath]
	  } else { set path {} }
	  
	  set DB [ static createDB $NAME $schema $path ]
	  
	  set state [ static rehydrate $NAME $schema ]
	  
	  $CONTAINER sets $state
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
		if { $ASYNC } {
			set keyValue [dict get $snapshot keyValue]
			if { [dict exists $QUEUE $keyValue] } {
				# If $keyValue already exists in our QUEUE then we need to batch its
				# snapshot with our new snapshot, cancel the current callback, and 
				# reschedule a callback for the $DELAY period.
				after cancel [dict get $QUEUE $keyValue after_id]
				set snapshot [mergeSnapshots [dict get $QUEUE $keyValue snapshot] $snapshot]
			}
			set after_id [ after $DELAY [namespace code [list my ResolveAsyncSnapshot $keyValue]] ]
			dict set QUEUE $keyValue [dict create \
				after_id $after_id \
				snapshot $snapshot
			]
		} else {
			# When sychronous snapshotting is enabled, every change to the state
			# will result in the snapshot being merged into the database synchronously.
			static SaveSnapshot $NAME $snapshot
		}
	}
	
	method ResolveAsyncSnapshot { keyValue } {
		set snapshot [dict get $QUEUE $keyValue snapshot]
		dict unset QUEUE $keyValue
		static SaveSnapshot $NAME $snapshot
	}
	
}


# Attempt to close the database $name . 
PersistMiddleware::static close { name } {
	tailcall sqlite3 [namespace parent]::db::$name close	
}

# Creates our Databases within the modules db namespace.  This way we can 
# keep all of the created database commands together and organized for later
# aggregation as-needed.
#
# ::tcm::module::state-persist-middleware::db::$StateID eval ... 
# 	The command will be returned to the instance so that it can call it easily
#   as needed.
PersistMiddleware::static createDB { name schema {path {}} } {
	if { $path eq {} } { set path [dict get [set [namespace current]::config] path] }
	set cmd [namespace parent]::db::${name}
	
	sqlite3 $cmd $path
	
	set localID [dict get $schema localID]

	$cmd eval {CREATE table IF NOT EXISTS _META (
		LOCAL_ID STRING PRIMARY KEY NOT NULL,
		KEY      STRING NOT NULL,
		ITEMS    STRING NOT NULL,
		REQUIRED STRING NOT NULL,
		TITLE    STRING,
		VERSION  STRING,
		UPDATED  TIMESTAMP
	)}
	
	if { [$cmd exists {SELECT LOCAL_ID FROM _META WHERE LOCAL_ID=$localID}] } {
		$cmd eval {SELECT * FROM _META WHERE LOCAL_ID=$localID} prevMeta {
			if { [dict get $schema items] ne $prevMeta(ITEMS) } {
				# When the schema of our state has changed we need to handle the
				# merging of the previous values so that we do not run into issues.
				#
				# We can't do this here as the table will be locked
				set pMeta [array get prevMeta]
			}
			break
		}
	}
	
	if { [info exists pMeta] } { 
		set createTable [ RebuildSchema $cmd $name $schema $pMeta ] 
	} else { set createTable 1 }
	
	if { $createTable } { 
		$cmd eval [string cat [format {CREATE table IF NOT EXISTS "%s"} $name] ( [TableSchema $schema] )] 
	}
	
	# When we have successfully built our table we will replace or add the data into our _META table.
	$cmd eval [format {
		INSERT OR REPLACE into _META
			VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%s')
	} [dict get $schema localID]  [dict get $schema key]   [dict get $schema items] \
		[dict get $schema required] [dict get $schema title] 1.0 [clock seconds]
	]
	
	return $cmd
}

proc TableSchema { schema } {
	set tschema {}
	set key [dict get $schema key]
	dict for { id params } [dict get $schema items] {
		if { $tschema ne {} } { append tschema ",\n" }
		append tschema [format {%s %s } $id [dict get $params type]]
		if { [dict exists $params isKey] }      { append tschema {PRIMARY KEY NOT NULL } }
		if { [dict exists $params isRequired] } { append tschema {NOT NULL } }
	}
	return $tschema
}

# When we need to rebuild our schema we will receive the prev and new schema data
# that we can then use to build a new table or add new columns into the schema
# if necessary.
#
# Our first check will check the new "required" items within the state and check to 
# make sure our schema indicates that we have all of those columns available.
proc RebuildSchema { cmd name schema prevMeta } {
	set newIDs [dict get $schema ids]
	set keyID  [dict get $schema key]
	set newRequired [dict get $schema required]
	set transferrable [concat $newRequired $keyID]
	set transferred 0
	
	if { [ $cmd eval { select name from sqlite_master where type = 'table' and name = $name } ] ne {} } {
		# When a previous table exists we need to make sure that we will be able to transfer the
		# previous schema to the old.  If we can't transfer the data then we need to remove the 
		# data all together. 
		#
		# We look at the actual columns set on the table rather than _META to be sure there are not 
		# any corruptions or disconnects that have somehow happened from the _META table. 
		$cmd eval [format {PRAGMA table_info('%s')} $name] column {
			set transferrable [lsearch -all -inline -not -exact $transferrable $column(name)]
		}; unset column

		if { $transferrable eq {} } {
			# If all of the items from $transferrable are no longer there then we should be
			# able to transfer the old data into the new schema.
			#
			# We will also attempt to transfer when all the required keys were previously
			# available but one or more may now be optional.  In this case we will attempt
			# the transfer.  Since required items are flagged with NOT NULL, our transaction
			# will fail should any of the required items not be available at which point we will
			# automatically revert to our alternative options.
			#
			# We do this by first creating a new table, building the new schema that will be used
			# then transfer matching keys over to the new table.  Any keys which are no longer apart
			# of the schema will be removed. 
			set transferred 1
			try {
				$cmd transaction {
					$cmd eval [format {DROP TABLE IF EXISTS "%s_worker"} $name]
					$cmd eval [string cat [format {CREATE table "%s_worker" } $name] ( [TableSchema $schema] )]
					$cmd eval [format {SELECT * FROM "%s"} $name] row {
						set i 0
						foreach column $row(*) {
							if { $column in $newIDs } {
								if { [info exists values] } { 
									append values {, } 
									append keys   {, }
								}
								if { $column in $newRequired && $row($column) eq {} } { 
									# This means that an item which was optional and is now required
									# does not exist.  In this case we currently will delete the data
									# and start over.
									#
									# We probably want to have a setting to allow modifying this behavior.
									throw error "A new required items is not present in a persistent entry: $column"
								}
				  			set val_${i} $row($column)
				  			append values :val_$i
				  			append keys $column
				  			incr i
							}
						}
						$cmd eval [format {INSERT INTO "%s_worker" (%s) VALUES (%s)} $name $keys $values]
					}
					$cmd eval [format {DROP TABLE "%s"} $name]
					$cmd eval [format {ALTER TABLE "%s_worker" RENAME TO "%s"} $name $name]
				}
			} on error {result options} {
				# Warning for now so we don't get confused if data is not where we think it 
				# should be.
				puts "\[state-db-persist\]: Could Not Transfer State: $result"
				set transferred 0
			}
		} else { throw error "NOT TRANSFERRABLE" }
	}
	# When a successful transfer was made, we will return 0 to tell the caller we do not
	# need them to create a new table.
	if { $transferred } { return 0 }
	# When we have determined that the state can not be transferred to the new schema, we 
	# need to determine what should be done with the previous values.
	#
	# TO DO : Provide configuration to allow for saving or backing up the data to a different
	#         database.  This way we can restore it if necessary.
	#
	# - For Now we will simply remove the table all together in this case.
	$cmd eval [format {DROP TABLE IF EXISTS "%s"} $name]
	return 1
}

PersistMiddleware::static SaveSnapshot { name snapshot {new 1} } {
	set cmd [namespace parent]::db::$name
	set items [dict withKey [dict get $snapshot items] value]
	
	set keyID [dict get $snapshot keyID]
	set keyValue [dict get $snapshot keyValue]

	# When we are saving a snapshot for the first time we need to check if the
	# row exists or not.  If it does not then we need to create it. 
	#
	# We need to take extra care to insure that we don't accidentally "inject" 
	# sql into the evaluation (or via a sql attack).
  set i 0
  $cmd transaction {
  	if { $new && [$cmd exists [format {SELECT "%s" FROM "%s" WHERE "%s" = :keyValue} $keyID $name $keyID]] } {
			dict for {k v} $items {
				if { [info exists update] } { append update {, } }
				set val_${i} $v
				append update [format {"%s" = %s} $k :val_${i}]
				incr i
			}
  		$cmd eval [format {UPDATE "%s" SET %s WHERE "%s" = :keyValue} $name $update $keyID]
  	} else {
  		set keys \"[join [dict keys $items] "\", \""]\"
  		foreach v [dict values $items] {
  			if { [info exists values] } { append values {, } }
  			set val_${i} $v
  			append values :val_$i
  			incr i
  		}
  		$cmd eval [format {INSERT INTO "%s" (%s) VALUES (%s) } $name $keys $values]
  	}
  }
}

PersistMiddleware::static eval { name args } {
	tailcall sqlite3 [namespace parent]::db::$name eval {*}$args	
}

# Called to rehydrate the state using the database value (if it exists). We select
# the entire table (dedicated to the state that calls it) and generate a valid "setter"
# which will set all the entries that have been saved.
PersistMiddleware::static rehydrate { name schema } {
	set cmd [namespace parent]::db::$name
	set keyID [dict get $schema key]
	set state [list]
	$cmd eval [format {SELECT * FROM "%s"} $name] row {
		set entry [dict create]
		foreach column $row(*) {
			dict set entry $column $row($column)
		}
		lappend state $entry
	}
	return $state
}

# Provides the global persist configuration information onto the PersistMiddleware
# instances using the "prop" command.
PersistMiddleware::static configure { args } {
	variable config
  dict with args {}
  
  # We require the path that should be used to save our databases.  Each
  # state container will have its own database file.
  if { ! [info exists -db] } {
    if { ! [dict exists $config db] } {
      throw error "You must provide a -db for the state-persist-middleware to use"
    }
  } else {
    dict set config path [file nativename [set -db]]
    file mkdir [file dirname [set -db]]
  }
  
  # Global async setting.  This will set the default to either synchronous
  # or asynchronous when we save our snapshots into the database.
  if { [info exists -async] } {
    dict set config async [set -async] 
  }
  
  # A command to be invoked during rehydration and saving of the state
  # to allow transforming before we save it.  For example, to allow for 
  # encryption.
  if { [info exists -command] } {
  	dict set config command [set -command]
  }
  
  if { [info exists -delay] } {
		dict set config delay [set -delay]	
  }
  
  # Do we want to load extensions for the db?
  if { [info exists -extensions] && [string is true -strict [set -extensions]] } {
		sqlite3 enable_load_extensions 1
  }
  
  set [namespace current]::config $config
}