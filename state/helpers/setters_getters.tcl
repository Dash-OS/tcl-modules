## Setters & Getters
# 	These commands are responsible for modifying or reading from the state
#		in some way.  Each command is passed through the state, routed as necessary
#		based on the arguments received.
#
#		We need to gather special information when we have subscriptions to fufill.
#		When we are working with a subscribed state, the snapshot variable will be
#		passed down with the execution of the command.  It will be modified to generate
#		an overall "snapshot" of the modification that was made.
#
#		#		Snapshots
#
#		A snapshot provides a detailed view of what occurred during the course of the
#		given action.  This is used by our subscription evaluator to efficiently determine
#		if any matching subscriptions should be triggered.
#
##	State Set Commands
package require json_tools
package require typeof

::oo::define ::state::Container method set data {
	if { $KEY eq "@@S" || [dict exists $data $KEY] } {
		if { $KEY eq "@@S" } {
			set stateKeyValue "@@S"
		} else {
			set stateKeyValue [dict get $data $KEY]
		}
		if { $READY && [dict exists $MIDDLEWARES onSnapshot] } {
			# We only create a snapshot when the state has active middlewares that
			# are expecting a snapshot.
			set snapshot [dict create \
				keyID    $KEY \
				keyValue $stateKeyValue \
				set      [dict keys $data] \
				created  [list] \
				changed  [list] \
				keys     [list] \
				removed  [list] \
				items    [dict create \
					$KEY [dict create value $stateKeyValue prev $stateKeyValue]
				]
			]
		}
		#catch { dict unset data $KEY }
		# Does the entry already exist? If not, create it!
		if { $stateKeyValue ni $ENTRIES } {
			if { [info exists snapshot] } {
				dict lappend snapshot created $KEY
			}
		  my CreateEntry $stateKeyValue
		}
		try {
		  entries::$stateKeyValue set $data
		} trap MISSING_REQUIRED {result} {
		  # If we receive this error then we need to remove the entry entirely.
		  # Once we have done that we will rethrow the error to the caller.
		  entries::$stateKeyValue destroy
		  throw MISSING_REQUIRED $result
		} trap ENTRY_INVALID {result} {
		  # This will occur when an entry fails due to a validation error and it
		  # can not revert to its previous values
		  entries::$stateKeyValue destroy
		  throw ENTRY_INVALID $result
		}
		if { [info exists snapshot] } {
			# If we have a snapshot we know that we need to evaluate middlewares.
			if { ( [dict exists $CONFIG stream] && [dict get $CONFIG stream] )
				|| ! [ string equal [dict get $snapshot changed] {} ]
				|| ! [ string equal [dict get $snapshot created] {} ]
				|| ! [ string equal [dict get $snapshot removed] {} ]
			} {
				# Each Middleware will have its "onSnapshot" method called with the snapshot
				# value. This only occurs by default if the snapshot changes.
				foreach middleware [dict values [dict get $MIDDLEWARES onSnapshot]] {
					$middleware onSnapshot $snapshot
					# If a middleware upvars and removes the snapshot, we will break
					if { ! [info exists snapshot] } {
            break
          }
				}
			}
		}
		return
	} else {
		throw error "You may only set Keyed stated when the given key is within your update snapshot! Expected $KEY within: $data"
	}
}

::oo::define ::state::Container method sets states {
	foreach entry $states { my set $entry }
}

::oo::define ::state::Entry method set data {
	upvar 1 snapshot snapshot
	if { $ITEMS eq {} } {
		# First time that we are setting this entry.  Check required values.
		set required [{*}$CONTAINER prop REQUIRED]
		set keys     [dict keys $data]
		if { ! [lhas $required $keys] } {
			throw MISSING_REQUIRED "State [namespace tail $CONTAINER] | Error | Required items are missing while setting entry $ENTRY_ID - received keys: \"$keys\" and require \"$required\""
		}
	}
	# Iterate through the received snapshot and set each of the items held within.
	dict for { k v } $data {
	  try {
	    set item [my item $k]
	    if { [info commands $item] ne {} } {
	      set exists [ $item set $ENTRY_ID $v ]
	    } else { set exists 0 }
  		if { ! $exists } {
  			if { $k in $ITEMS } {
          set ITEMS [lsearch -all -inline -not -exact $ITEMS $k]
        }
  		} elseif { $k ni $ITEMS } {
        lappend ITEMS $k
      }
		} trap VALIDATION_ERROR { result } {
		  # If a validation occurs we need to revert any values we have already set
		  foreach rkey [dict keys $data] {
		    if { $rkey eq $k } {
          continue
        }
		    set item [my item $rkey]
		    if { [info commands $item] ne {} } {
  		    if { ! [ $item revert $ENTRY_ID ] } {
  		      if { $rkey eq $KEY } {
  		        [self] destroy
  		      } else {
  		        my remove $rkey
  		      }
  		    }
		    }
		  }
		  throw VALIDATION_ERROR $result
		}
	}
	if { [info exists snapshot] } {
		# The actual entry key value

		# All the current items this entry has
		dict set snapshot keys [concat $KEY $ITEMS]
		# When we need to send commands to the entry later
		dict set snapshot refs entry [self]
	}
	return
}

::oo::define ::state::Item method set {key value {force 0}} {
	upvar 1 snapshot snapshot
	if { [dict exists $VALUES $key] } {
		set prev [dict get $VALUES $key]
	} elseif { $value ne {} } {
		set prev {}
	} else {
    return 0
  }
	if { $value eq {} } {
		# Setting an item to a value of {} will remove it from the state.
		# an empty value shall be treated as "null" for our purposes and may
		# be further interpreted by the higher-order-procedures.
		# -- Still have to determine if this is the appropriate logic to use.
		if { $REQUIRED && ! $force } {
      throw REMOVE_REQUIRED_ITEM "State [namespace tail $CONTAINER] | Error | $ITEM_ID is a required item but you tried to remove it in entry $key"
    }
		if {[dict exists $VALUES $key]} {
      dict unset VALUES $key
    }
		if {[dict exists $PREV $key]} {
      dict unset PREV $key
    }
		if {[info exists snapshot]} {
			dict lappend snapshot removed $ITEM_ID
			if { [dict exists $snapshot set] } {
			  dict set snapshot set [lsearch -all -inline -not -exact [dict get $snapshot set] $ITEM_ID]
			}
			dict set snapshot items $ITEM_ID [dict create value {} prev $prev]
		}
		return 0
	} elseif { ! [ my validate value ] } {
		throw VALIDATION_ERROR "State [namespace tail $CONTAINER] | Error | Entry $key | $value does not match item ${ITEM_ID}'s schema: $TYPE"
  } else {
  	if { [info exists snapshot] } {
  		if { $prev eq {} } {
  			dict lappend snapshot created $ITEM_ID
  			dict set snapshot items $ITEM_ID [dict create value $value prev {} ]
  		} else {
  			dict set snapshot items $ITEM_ID [dict create value $value prev $prev]
  			if { [string equal $prev $value] } {
          return 1
        } else {
  				dict lappend snapshot changed $ITEM_ID
  			}
  		}
		}
  	dict set VALUES $key $value
		dict set PREV   $key $prev
  }
  return 1
}

::oo::define ::state::Item method revert entry_id {
  if { [dict exists $VALUES $entry_id] } {
    set value [dict get $VALUES $entry_id]
  } else { set value {} }
  if { [dict exists $PREV $entry_id] } {
    set prev [dict get $PREV $entry_id]
  } else {
    set prev {}
  }
  if { $prev eq {} } {
    if { $REQUIRED } {
      throw ENTRY_INVALID "State [namespace tail $CONTAINER] | Error | $entry_id item $ITEM_ID is required but now invalid, the entry will be removed"
    } else {
      # Remove the item all together
      return 0
    }
  } else {
    # We simply set the value to the previous value while keeping previous
    # the same.  This is because we don't want multiple invalidation attempts
    # to end up removing a value all together and also don't want them to end up
    # causing issues with subscriptions which depend on changing values.
    dict set VALUES $entry_id $prev
  }
  return 1
}

##	State Get Commands

::oo::define ::state::Container method get {op args} {
	set value {}
	if { $KEY eq "@@S" } {
		set args [lassign $args items]
		if { [info commands entries::$KEY] ne {} } {
			set value [entries::$KEY get $op $items {*}$args]
			dict unset value $KEY
		}
	} elseif { $ENTRIES ne {} } {
		set items   [lassign $args entries]
		set entries [expr { $entries eq {} ? $ENTRIES : $entries }]
		foreach entry $entries[set entries {}] {
			if { $entry in $ENTRIES } {
				dict set value $entry [entries::$entry get $op $items]
			}
		}
	} else { return }
	return $value
}

::oo::define ::state::Entry method get {op {items {}} args} {
  set value {}
	set items [expr { $items eq {} ? $ITEMS : $items }]
	foreach itemID $items {
		if { $itemID ni $ITEMS } {
      continue
    }
		set item [my item $itemID]
		if { [info commands $item] ne {} } {
  	  dict set value $itemID \
  			[ $item get $op $ENTRY_ID {*}$args ]
	  }
	}
	return $value
}

::oo::define ::state::Item method get {op entryID args} {
	if { [string equal $op SNAPSHOT] } {
		return [ dict create value [dict get $VALUES $entryID {*}$args] prev [dict get $PREV $entryID {*}$args] ]
	} elseif { [string equal $op ENTRY_REMOVED] } {
	  # This is used to tell the item to expect that it will be removed so that we
	  # can capture the appropriate snapshot data during item removal.
	  return [ dict create value {} prev [dict get $VALUES $entryID {*}$args] ]
	} else {
	  if { [info exists $op] && [dict exists [set $op] $entryID {*}$args] } {
	    return [ dict get [set $op] $entryID {*}$args ]
	  } else {
	    throw error "$op does not exist in item [self]"
	  }
	}
}

## JSON / Serialization Commands

::oo::define ::state::Container method json {op args} {
	set json [json start]
	try {
		$json map_open
		if { $KEY eq "@@S" } {
			set args  [lassign $args items]
			if { $items eq "@@S" } {
			  set args [lassign $args items]
			}
			set value [entries::$KEY json $json $op $items {*}$args]
		} else {
			set args [lassign $args entries items]
			set entries [expr { $entries eq {} ? $ENTRIES : $entries }]
			foreach entry $entries {
				$json map_key $entry map_open
				if { $entry in $ENTRIES } {
					entries::$entry json $json $op $items {*}$args
				}
				$json map_close
			}
		}
		$json map_close
		set body [json done $json]
	} on error {result options} {
		# If we encounter an error, we need to conduct some cleanup, then we throw
		# the error to the next level.
		catch {
      $json delete
    }
		throw error $result
	}
	return $body
}

# state serialize MyState \
#   -meta    [list ] \
#   -op      snapshot \
#   -entries
::oo::define ::state::Container method serialize args {
  set json [json start]
  $json map_open
  if { [dict exists $args -meta] } {
    my serialize_meta $json [dict get $args -meta]
  }
  if { [dict exists $args -context] } {
    set parsed [::json parse [json typed [dict get $args -context]]]
    $json map_key context {*}$parsed
  }
  if { [dict exists $args -entries] } {
    set parsed [::json parse [state json [namespace tail [self]] {*}[dict get $args -entries]]]
    $json map_key entries {*}$parsed
  }
  $json map_close
  set body [json done $json]
}

::oo::define ::state::Container method serialize_meta { json values } {
  $json map_key meta map_open
    $json map_key state_id string [namespace tail [self]]
    if {$values eq "all"} {
      set values [list KEY READY ENTRIES REQUIRED CONFIG SCHEMA SUBSCRIBED MIDDLEWARES ITEMS]
    }
    foreach value $values {
      set val [set [string toupper $value]]
      switch -- [::typeof $val] {
        boolean {
          $json map_key [string tolower $value] boolean $val
        }
        number {
          $json map_key [string tolower $value] number $val
        }
        list {
          # workaround since number no longer allows invalid values
          set parsed [::json parse [json typed $val]]
          $json map_key [string tolower $value] {*}$parsed
        }
        dict {
          set parsed [::json parse [::json typed $val]]
          $json map_key [string tolower $value] {*}$parsed
        }
        string - default {
          $json map_key [string tolower $value] string $val
        }
      }
    }
  $json map_close
}

::oo::define ::state::Entry method json {json op items args} {
	set items [expr { $items eq {} ? $ITEMS : $items }]
	foreach itemID $items {
		${ITEMS_PATH}::$itemID json $json $op $ENTRY_ID {*}$args
	}
	return
}

::oo::define ::state::Item method json {json op entryID args} {
	my serialize $json $ITEM_ID $op [my get $op $entryID] {*}$args
}

## Remove Commands

::oo::define ::state::Container method remove args {
  if { $KEY eq "@@S" } {
	  set key_value "@@S"
	  set args [lassign $args items]
	  my remove_key $key_value $items {*}$args
	} else {
	  set args [lassign $args remove_keys items]
	  if { $remove_keys eq {} } {
	    set remove_keys $ENTRIES
	  }
		foreach key_value $remove_keys {
		  my remove_key $key_value $items {*}$args
		}
	}
	return
}

::oo::define ::state::Container method remove_key {key_value items args} {
  if { $READY && [dict exists $MIDDLEWARES onSnapshot] } {
		# We only create a snapshot when the state has active middlewares that
		# are expecting a snapshot.
		set snapshot [dict create \
			keyID    $KEY \
			keyValue $key_value \
			removed  [list] \
			created  [list] \
			changed  [list] \
			keys     [list] \
			set      [list]
		]
	}
	if { $KEY eq "@@S" } {
		entries::$KEY remove $items {*}$args
	} elseif { $key_value in $ENTRIES } {
    entries::$key_value remove $items {*}$args
  } else { return }
  if { [info exists snapshot] } {
    foreach middleware [dict values [dict get $MIDDLEWARES onSnapshot]] {
			$middleware onSnapshot $snapshot
			if { ! [info exists snapshot] } {
        break
      }
		}
  }
	return
}

::oo::define ::state::Entry method remove {items args} {
  upvar 1 snapshot snapshot
  if { $items eq {} } {
    if { [info exists snapshot] } {
      dict set snapshot removed $ITEMS
      dict set snapshot items [my get ENTRY_REMOVED]
      dict set snapshot entry_removed 1
    }
    my destroy
    return
  } else {
    foreach itemID $items {
      set item [my item $itemID]
      if { [info commands $item] ne {} } {
        $item set $ENTRY_ID {}
        set ITEMS [lsearch -all -inline -not -exact $ITEMS[set ITEMS ""] $itemID]
      }
  	}
  	if { [llength $ITEMS] == 0 } {
  	  # When we have no more items, we remove ourselves
  	}
  }
}

::oo::define ::state::Container method query query {
  if { $ENTRIES eq {} || $KEY eq "@@S" } {
    return
  }
	set results [list]
	foreach or [dict get $query ors] {
		set filtered $ENTRIES
		foreach filter $or {
			set filtered [my filter_entries $filtered $filter]
			if { $filtered eq {} } {
        break
      }
		}
		if { $filtered ne {} } {
      lappend results $filtered
    }
	}
	return [lsort -unique [concat {*}$results]]
}

::oo::define ::state::Container method filter_entries { entries filter } {
  if { [dict get $filter key] eq $KEY } {
    dict with filter {}
    set entries [lmap value $entries {
      set prev $value
      if { [try [dict get $filter evaluate]] } {
        set value
      } else {
        continue
      }
    }]
    return $entries
  } elseif { [info commands items::[dict get $filter key]] ne {} } {
    return [items::[dict get $filter key] filter $filter $entries ]
  }
}

::oo::define ::state::Item method filter { filter entries args } {
  set values [dict filter $VALUES key {*}$entries]
  if { $values eq {} } {
    return
  }
  return [dict keys [run \
    -scoped \
    -vars [list ITEM_ID] \
    -with [dict merge $filter [dict create key $ITEM_ID VALUES $values PREV $PREV]] \
    {
      set keys $key
      set FINAL [dict filter $VALUES script { entry_id value } {
        set prev [dict get $PREV $entry_id]
        if { [dict exists $modifiers before-eval] } {
          if { [dict exists $modifiers before-eval] } {
						foreach modifier [dict get $modifiers before-eval] {
							try $modifier
						}
					}
        }
        set result [ try $evaluate ]
        if { [dict exists $modifiers after-eval] } {
          if { [dict exists $modifiers after-eval] } {
						foreach modifier [dict get $modifiers after-eval] {
							try $modifier
						}
					}
        }
        set result
      }]
    }
  ]]
}
