namespace eval ::state              {}
namespace eval ::state::containers  {}
namespace eval ::state::mixins      {}
namespace eval ::state::middleware  {}
namespace eval ::state::parse       {}
package require list_tools
package require oo::module
package require state::registry::type
package require state::registry::query
package require state::registry::middleware
::oo::class create ::state::API
module create ::state::Container {}
module create ::state::Entry {}
module create ::state::Item {}
package require state::parser::parser
package require state::classes::api
package require state::classes::container
package require state::classes::entry
package require state::classes::item

source [file normalize [file join [file dirname [info script]] state helpers setters_getters.tcl]]

# ::state::define allows us to extend various parts of our state with new methods or 
# capabilities.  Its purpose is to allow a "plugin-like" system for extending what 
# the state can or does do.
proc ::state::define { what with args } {
  switch -nocase -- $what {
    api {
      if { $with eq "method" } {
        set args [ lassign $args name withArgs withBody ]
        if { [llength $args] } { set withBody [string cat [list try [join $args "\;"]] \; $withBody] }
        ::oo::define ::state::API method $name $withArgs $withBody
      } else {
        ::oo::define ::state::API $what $with {*}$args
      }
    }
  }
}

::state::API create ::state
