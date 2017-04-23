# State ::state::Entry
#		State Entries are responsible for coordinating a set of items which 
#		are located within an Item class.  They are responsible for aggregating
#		the denormalized data when required.
#
::oo::define ::state::Entry {
	variable KEY
	variable CONTAINER
	variable ENTRY_ID
	variable ITEMS
	variable ITEMS_PATH
}

::oo::metaclass::define ::state::Entry constructor { container entry_id key schema } {
	set CONTAINER  $container
	set KEY        $key
	set ENTRY_ID   $entry_id
	set ITEMS      [list]
	set ITEMS_PATH ::state::Container::[namespace tail $container]::items
}

::oo::define ::state::Entry method item { itemID } {
	return ${ITEMS_PATH}::$itemID
}

::oo::define ::state::Entry destructor {
	foreach itemID $ITEMS {
		set ref [my item $itemID]
		if { [info commands $ref] ne {} } {
			$ref set $ENTRY_ID {} 1
		}
	}
	{*}$CONTAINER remove_entries [list $ENTRY_ID]
}