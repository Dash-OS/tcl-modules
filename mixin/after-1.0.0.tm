if 0 {
  @ ::mixin::after
    a mixin for objects to easily schedule via [after]
    which are automatically cleaned up when the object
    is destroyed.

    @method after | $id $ms {*}$args
      schedule an [after] to occur and save it by its id value.
      returns the id back to the caller which can be used to cancel
      the [after].

    @method cancel | ...$args
      cancels any after ids which are provided within the args value.
      if the given id is not scheduled it is ignored.
}
namespace eval ::mixin {}

if {[info command ::mixin::after] eq {}} {
  ::oo::class create ::mixin::after {}
}

::oo::define ::mixin::after {
  variable @@AFTER_IDS__
}

::oo::define ::mixin::after destructor {
  if {[info exists @@AFTER_IDS__]} {
    dict for {name id} ${@@AFTER_IDS__} {
      after cancel $id
    }
  }
  next
}

::oo::define ::mixin::after method after {id ms args} {
  if {[info exists @@AFTER_IDS__] && [dict exists ${@@AFTER_IDS__} $id]} {
    after cancel [dict get ${@@AFTER_IDS__} $id]
  }
  dict set @@AFTER_IDS__ $id [after $ms [list ::apply [list {id scripts} {
    my variable @@AFTER_IDS__
    dict unset @@AFTER_IDS__ $id
    uplevel #0 {*}$scripts
  } [namespace current]] $id $args]]
  return $id
}

::oo::define ::mixin::after method cancel args {
  if {![info exists @@AFTER_IDS__]} {return}
  foreach name $args {
    if {[dict exists ${@@AFTER_IDS__} $name]} {
      after cancel [dict get ${@@AFTER_IDS__} $name]
      dict unset @@AFTER_IDS__ $name
    }
  }
}
