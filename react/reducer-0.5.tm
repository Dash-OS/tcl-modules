package require react 

namespace eval ::react {}

proc ::react::register_reducer { callback } {
  if { $callback eq {} } { unset -nocomplain ::React::CallReducer }
  set ::react::CallReducer $callback
}

proc ::react::dispatch { event args } {
  variable CallReducer
  if { [info exists CallReducer] } {
    {*}$CallReducer $event {*}$args
    return 1
  } else { return 0 }
}

Component create ::react::reducer {
  variable PROPS
  
  # Receives Events, translates them to state which will in-turn be proliferated
  # to our children.
  method componentWillMount {} {
    react register_reducer [callback my event]
  }
  
  method componentWillUnmount {} {
    react register_reducer {}
  }
  
  # We will receive events from our dispatcher and react to them by appropriately
  # setting the state based on the values we receive.  Those can then be sent into 
  # our UI as-needed based on the context.
  method event {event args} {
    switch -- $event {
      goto {
        {*}[dict get $PROPS goto] {*}$args
      }
      store {
        set data [ lassign $args key ]
        set store [{*}[dict get $PROPS store]]
        if { [dict exists $store $key] } {
          set reduce [dict get $store $key] 
        } else { set reduce [dict create] }
        set reduce [dict merge $reduce $data]
        dict set store $key $reduce
        {*}[dict get $PROPS store] $store
      }
      default {
        puts stderr "event $event is unknown"
      }
    }
  }
  
}
