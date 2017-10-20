
source [file normalize \
  [file join \
    [file dirname [info script]] parse_attribute.tcl \
  ]
]

proc ::state::parse::SetArgs {} {
  uplevel 1 {
    set setters {}
    set script {}
    set scriptArgs {}
    switch -- [llength $args] {
      1 { lassign $args query }
      2 { lassign $args setters query }
      3 { lassign $args query scriptArgs script }
      4 { lassign $args setters query scriptArgs script }
      default { set query {} }
    }
  }
}

variable ::state::parse::Keywords {
  config				{ args 1    	}
  middlewares   { args 1      }
  required      { args 1      }
  vendor				{ args 1			}
  items					{ args 1      }
  conditions		{ args 1			}
  attributes		{ args 1			}
  state 		    { args {2 3}	}
  response      { args 1      }
  evaluate			{ args 2			}
  conditions		{ args 1			}
  id						{ args 1			}
  title					{ args 1			}
  titles				{ args 1			}
  descriptions	{ args 1			}
  default				{ args 1			}
  formatters    { args 1      }
  every         { args 1      }
  in            { args 1      }
  at            { args 1      }
}

variable ::state::parse::Keys [dict keys $::state::parse::Keywords]

# Parse the data structure and normalize it into a valid
# tcl dictionary.  This step allows us to handle situations
# where we may have attributes that define more than a
# key/value pair.
proc ::state::parse::Format args {
  if {[llength $args] == 1} {
    set args [lindex $args 0]
  }
  set tempDict [dict create]
  set i 0
  set multi 0
  foreach item $args {
    set item [string trim $item]
    if { $i == 0 } {
      set keyword {}
    }
    if {$keyword eq {}} {
      if {$item ni $::state::parse::Keys} {
        throw error "$item is not a known keyword"
      }
      set setKeyword 1
    }
    if {[string is true -strict $multi] && $item in $::state::parse::Keys} {
      set setKeyword 1
    }
    if {$setKeyword} {
      set keyword $item
      set keywordArgs [dict get $::state::parse::Keywords $item args]
      set i [lindex $keywordArgs end]
      set setKeyword 0
      if {[llength $keywordArgs] > 1} {
        set multi 1
      } else {
        set multi 0
      }
      continue
    }
    dict lappend tempDict $keyword $item
    incr i -1
  }
  return $tempDict
}

proc ::state::parse::state {localID args} {
  SetArgs
  return [Evaluate $localID [Format $query] $setters]
}

proc ::state::parse::query {localID args} {
  SetArgs
  return [Evaluate $localID $query $setters]
}

proc ::state::parse::subscription {localID args} {
  SetArgs
  return [dict create \
    script       [string trim $script] \
    subscription [Evaluate $localID $query $setters]
  ]
}

proc ::state::parse::task {localID args} {
  SetArgs
  return [dict create \
    script [string trim $script] \
    task   [Evaluate $localID [Format $query] $setters]
  ]
}

proc ::state::parse::command {localID args} {
  SetArgs
  return [Evaluate $localID [Format $query] $setters]
}

proc ::state::parse::event {localID args} {
  SetArgs
  return [Evaluate $localID [Format $query] $setters]
}

proc ::state::parse::Evaluate {localID container {setters {}} {scriptArgs {}}} {
  set parsedDict [dict create localID $localID]
  dict for {attribute data} $container {
    try {
      if { [llength $data] == 1 } {
        set data [lindex $data 0]
      }
      parser::$attribute
    } on error {result options} {
      ::onError $result $options "While Parsing $localID attribute $attribute"
    }
  }
  dict set parsedDict setters $setters
  return $parsedDict
}
