namespace eval ::state {}
namespace eval ::state::register {}
namespace eval ::state::register::registry {}

variable ::state::register::registry::types [dict create]
variable ::state::register::registry::type_keys [list]

package require state::mixins::type_mixin

# registering a type should be in the following form:
proc ::state::register::type { type schema } {
	foreach { func fargs script } $schema {
		set nargs  [::llength $fargs]
		set lambda [::list ::apply [ ::list $fargs $script ] ]
		dict set registry::types $type $func [dict create args $fargs func $lambda]
	}
	set registry::type_keys [dict keys $registry::types]
}

proc ::state::type type {
	return [dict get $register::registry::types $type]
}

proc ::state::types {} {
	return $register::registry::type_keys
}

proc ::state::register_default_types {} {
  ::state::register::type bool {
  	validate {v}   { ::string is bool -strict $v }
  	post     {v}   { ::expr {bool($v)} }
  	json     {k v j} { $j map_key $k bool $v }
  }
  ::state::register::type ip {
  	pre {v} { ::ip normalize $v }
  	validate {v} { ::expr {$v ne {}} }
  	json {k v json} { $json map_key $k string $v }
  }
  ::state::register::type number {
  	validate {v} {  ::string is double -strict $v }
  	json {k v json} { $json map_key $k number $v }
  }
  ::state::register::type string {
  	json {k v json} { $json map_key $k string $v }
  }
  ::state::register::type mac {
    validate {v} {regexp -nocase {^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$} $v}
    toJSON {k v json} {$json map_key $k string $v}
  }
  ::state::register::type json {
    validate {v} { json validate $v }
    toJSON {k v json} {$json map_key $k string $v}
  }
  ::state::register::type enum {
    validate {v p} { expr {$v in $p} }
    toJSON {k v json} {
      if {[string is entier -strict $v]} { 		    $json map_key $k number $v
      } elseif {[string is bool -strict $v]} { 	  $json map_key $k bool   $v
      } else {							                      $json map_key $k string $v
      }
    }
  }
  ::state::register::type ni {
    validate {v p} { expr {$v ni $p} }
    toJSON {k v json} {
      if {[string is entier -strict $v]} { 		    $json map_key $k number $v
      } elseif {[string is bool -strict $v]} { 	  $json map_key $k bool   $v
      } else {							                      $json map_key $k string $v
      }
    }
  }
  ::state::register::type match {
    validate {v p} { string match $p $v }
    toJSON {k v json} {
      if {[string is entier -strict $v]} { 		    $json map_key $k number $v
      } elseif {[string is bool -strict $v]} { 	  $json map_key $k bool   $v
      } else {							                      $json map_key $k string $v
      }
    }
  }
  ::state::register::type include {
    validate {v p} { string match *${p}* $v }
    toJSON {k v json} {
      if {[string is entier -strict $v]} { 		    $json map_key $k number $v
      } elseif {[string is bool -strict $v]} { 	  $json map_key $k bool   $v
      } else {							                      $json map_key $k string $v
      }
    }
  }
  ::state::register::type range {
    validate {v p} { expr { $v >= [lindex $p 0] && $v <= [lindex $p 1]} }
    toJSON {k v json} {
      if {[string is entier -strict $v]} { 		    $json map_key $k number $v
      } else {							                      $json map_key $k string $v
      }
    }
  }
  ::state::register::type percent {
    validate {v} { expr { $v >= 0 && $v <= 100 } }
    toJSON {k v json} {$json map_key $k number $v}
  }
  ::state::register::type greater {
    validate {v p} { expr { $v > $p } }
    toJSON {k v json} {
      if {[string is entier -strict $v]} { 		    $json map_key $k number $v
      } else {							                      $json map_key $k string $v
      }
    }
  }
  ::state::register::type less {
    validate {v p} { expr { $v < $p } }
    toJSON {k v json} {
      if {[string is entier -strict $v]} { 		    $json map_key $k number $v
      } else {							                      $json map_key $k string $v
      }
    }
  }
  ::state::register::type array {
    validate {v} { string is list -strict $v }
    toJSON {k v json} {
      $json map_key $k array_open
      foreach e $v {
        if {$e eq {}} { continue }
        if {[string is entier -strict $e]}     { 		$json number $e
        } elseif {[string is bool -strict $e]} { 	  $json bool   $e
        } else {							                      $json string $e
        }
      }
      $json array_close
    }
  }
  
  rename ::state::register_default_types {}
    
}

::state::register_default_types
