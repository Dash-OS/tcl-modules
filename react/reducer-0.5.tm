package require react 

namespace eval ::react {}

proc ::react::register_reducer args {
  puts reg
  if { $args eq {} } { unset -nocomplain ::react::reducer_callbacks }
  set ::react::reducer_callbacks $args
}

proc ::react::dispatch { event args } {
  if { ! [info exists ::react::reducers] } { return 0 }
  if { $args eq {} } { lappend args {} }
  if { [info exists ::react::reducer_callbacks] && [dict exists $::react::reducer_callbacks onEvent] } {
    {*}[dict get $::react::reducer_callbacks onEvent] $event {*}$args
    return 1
  } else { puts no ; return 0 }
}

proc ::react::reduce args {
  set script   [lindex $args end]
  set argnames [lindex $args end-1]
  set path     [lrange $args 0 end-2]
  
  # If it reaches the end we always return the $store so it remains unchanged
  set script [join [list \
    $script \
    [format {return [set %s]} [lindex $argnames 0]] 
  ] \;]

  if { [lindex $argnames end] ne "args" } { lappend argnames args }
  
  dict set ::react::reducers $path [list ::apply [list $argnames $script]]
}

proc ::react::remove_reducer args {
  if { [info exists ::react::reducers] && [dict exists $::react::reducers {*}$args] } {
    dict unset ::react::reducers {*}$args
  }
}

proc ::react::default_store { args } {
  if { $args eq {} } {
    unset -nocomplain ::react::default_store
    return
  } elseif { [llength $args] > 1 } {
    dict set ::react::default_store {*}$args
  } else {
    set ::react::default_store [lindex $args 0]
  }
}

# Get the React Store
proc ::react::store { {action get} args } {
  if { 
    [info exists ::react::reducer_callbacks] 
    && [dict exists $::react::reducer_callbacks $action] 
  } {
    return [{*}[dict get $::react::reducer_callbacks $action] {*}$args]
  } elseif { $action eq "get" && [info exists ::react::default_store] } {
    return $::react::default_store
  }
}

Component create ::react::reducer {
  variable PROPS STORE
  
  # Receives Events, translates them to state which will in-turn be proliferated
  # to our children.
  method componentWillMount {} {
    puts mount
    if { [info exists ::react::default_store] } {
      set STORE $::react::default_store
    } else {
      set STORE [dict create]
    }
    react register_reducer \
      onEvent [callback my event] \
      set     [callback my set_store] \
      get     [callback my get_store]
  }
  
  method componentWillUnmount {} {
    react register_reducer {}
  }
  
  method creator {} {
    puts creator
    return [list namespace inscope [ \
      [namespace parent [namespace qualifiers [self]]] @namespace] \
    my]
  }
  
  # We will receive events from our dispatcher and react to them by appropriately
  # setting the state based on the values we receive.  Those can then be sent into 
  # our UI as-needed based on the context.
  method event {event args} {
    puts event
    set new_store $STORE
    dict for { path script } $::react::reducers {
      if { [dict exists $new_store {*}$path] } {
        set op_store [dict get $new_store {*}$path] 
      } else { set op_store [dict create] }
      set op_store [{*}$script $op_store $event {*}$args]
      dict set new_store {*}$path $op_store
    }
    my set_store $new_store
  }
  
  # Get the store.  This can also be called by using [react store]
  method get_store {} { return $STORE }
  
  # This method will set the store and update all attached components.  Note that
  # this is almost always a bad idea.  We should always try to use our reducers.
  method set_store store { 
    if { $STORE ne $store } {
      set STORE $store
      my store_update
    }
  }
  
  method store_update {} { {*}[my creator] forceUpdate }
  
}
