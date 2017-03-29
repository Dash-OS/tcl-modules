# Item
#   Item holds an index of our values.  This index is setup as a dict of values
#   where the keys of the dict are the entry keys and the values are the values
#   themselves.  This structure allows us to parse the entries and values easily
#   during queries.  We used to have a separate "index" class setup this way but 
#   it was found that simply setting values this way is far more efficient.
#
# Mixins::Typed expects a variable "TYPE" to be defined which is any type in the
# type registry.
package require state::mixins::type_mixin

::oo::define ::state::Item {
  mixin -append ::state::mixins::typed
  variable ITEM_ID
  variable CONTAINER
  variable VALUES
  variable PREV
  variable TYPE
  variable PARAMS
  variable REQUIRED
}


::oo::define ::state::Item constructor {container schema} {
  set CONTAINER $container
  set ITEM_ID [dict get $schema id]
  if { [dict exists $schema type] } {
    set TYPE [dict get $schema type]
  } else { set TYPE {} }
  if { [dict exists $schema params] } {
    set PARAMS [dict get $schema params] 
  } else { set PARAMS [dict create] }
  if { [dict exists $schema isRequired] } {
    set REQUIRED [dict get $schema isRequired] 
  } else { set REQUIRED 0 }
  set VALUES [dict create]
  set PREV   [dict create]
}

::oo::define ::state::Item destructor {
  puts "Item is being Destroyed! [namespace current] - [self]"
}