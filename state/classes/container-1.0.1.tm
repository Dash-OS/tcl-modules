::oo::define ::state::Container {
  variable KEY READY ENTRIES REQUIRED CONFIG SCHEMA
  variable SUBSCRIBED MIDDLEWARES ITEMS SINGLETON SHARED
}

::oo::metaclass::define ::state::Container constructor schema {
  #puts "::state::Container [namespace tail [namespace current]] \n Schema: $schema \n "
  set READY    0
  set KEY      [dict get $schema key]
  set REQUIRED [dict get $schema required]

  if { [dict exists $schema config] } {
    set CONFIG [dict get $schema config]
    dict unset schema config
  } else {
    set CONFIG [dict create]
  }

  if { [dict exists $CONFIG shared] } {
    set SHARED [dict get $CONFIG shared]
  } else {
    set SHARED 0
  }

  set ENTRIES     [list]
  set SCHEMA      $schema
  set MIDDLEWARES [dict create]
  set SUBSCRIBED  1

  if { $KEY eq {} } {
    set KEY "@@S"
    set SINGLETON 1
  } else {
    set SINGLETON 0
  }

  my CreateItems
  if { [dict exists $SCHEMA default] && $KEY eq "@@S" } {
    # Default is only available for singleton state and it is
    # applied before middlewares.
    my set [dict get $SCHEMA default]
    dict unset SCHEMA default
  }
  my ApplyMiddlewares
}

::oo::define ::state::Container destructor {
  # puts "[self] is being destroyed!"
  my middleware_event onDestroy
}

::oo::define ::state::Container method CreateItems {} {
  dict for {itemID params} [dict get $SCHEMA items] {
    my CreateItem $itemID $params
  }
}

::oo::define ::state::Container method CreateItem { itemID params } {
  ::state::Item create items::$itemID [self] $params
  lappend ITEMS $itemID
}

::oo::define ::state::Container method CreateEntry { entryID } {
  ::state::Entry create entries::$entryID [self] $entryID $KEY $SCHEMA
  lappend ENTRIES $entryID
}

::oo::define ::state::Container method prop { what {value {}} } {
  set what [string toupper $what]
  if { ! [info exists $what] } {
    throw error "Property $what does not exist in [self]"
  }
  return [set $what]
}

::oo::define ::state::Container method entries {} {
  return $ENTRIES
}

::oo::define ::state::Container method items {} {
  return $ITEMS
}

::oo::define ::state::Container method remove_entries { entryIDs } {
  if { ! [info exists ENTRIES] } { return }
  foreach entryID $entryIDs {
    set ENTRIES [lsearch -all -inline -not -exact $ENTRIES[set ENTRIES ""] $entryID]
  }
}

::oo::define ::state::Container method apply_middleware { middlewareID } {
  # Apply a new middleware to a state ::state::Container.  This may have
  # adverse effects depending on the middleware type.
  set middlewares [dict get? $SCHEMA middlewares]
  if { $middlewareID ni $middlewares } { lappend middlewares $middlewareID }
  dict set SCHEMA middlewares $middlewares
  my ApplyMiddlewares
}

::oo::define ::state::Container method ApplyMiddlewares {} {
  set onregisters [list]
  if { [dict exists $SCHEMA middlewares] } {
    set MiddlewareRegistry [::state::middlewares]

    foreach middlewareID [dict get $SCHEMA middlewares] {
      if { [info command middlewares::$middlewareID] ne {} } {
        # Middleware alraedy applied.
        continue
      }
      set Middleware [dict get $MiddlewareRegistry $middlewareID]
      set MiddlewareClass  [dict get $Middleware middleware]
      set MiddlewareConfig [dict get $Middleware config]
      set MiddlewareMixins [dict get $Middleware mixins]

      set instance [$MiddlewareClass create middlewares::$middlewareID [self] $CONFIG $MiddlewareConfig]
      set methods [info class methods $MiddlewareClass]

      if { "onSnapshot" in $methods } {
        dict set MIDDLEWARES onSnapshot $middlewareID $instance
      }

      if { [dict exists $MiddlewareMixins container] } {
        ::oo::objdefine [self] mixin -append [dict get $MiddlewareMixins container]
      }

      if { [dict exists $MiddlewareMixins item] } {
        set mixin [dict get $MiddlewareMixins item]
        foreach itemID $ITEMS { ::oo::objdefine items::$itemID mixin -append $mixin }
      }
      if { "onRegister" in $methods } {
        lappend onregisters [list $middlewareID $instance]
      }
    }
  }
  foreach middleware $onregisters {
    lassign $middleware middlewareID instance
    {*}$instance onRegister $SCHEMA $CONFIG
  }
  set READY 1
}

::oo::define ::state::Container method middleware_event {event args} {
  if { ! [string match "on*" $event] } { set event "on[string totitle $event]" }
  foreach middleware [info commands middlewares::*] {
    if { $event in [info class methods [info object class $middleware]] } {
      try {
        $middleware $event {*}$args
      } on error {result options} {
        ::onError $result $options "While triggering a Middleware Event $event on $middleware"
      }
    }
  }
}

::oo::define ::state::Container method events value {
  set READY [string is true -strict $value]
}
