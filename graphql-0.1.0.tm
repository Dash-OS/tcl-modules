package require json_tools

# set QUERY {query (
#   $resolve: String!
# ) {
#   onCluster(
#     resolve: $resolve
#   ) {
#     AppStatus {
#       status
#       isAuthenticated
#     }
#   }
# }}

# proc handleGraphRequest request {
#   set data   [json get $request]
#   set parsed [::graphql::parse $data]
#   puts $parsed
#   if {[dict exists $parsed requests]} {
#     foreach {request params} [dict get $parsed requests] {
#       puts "Request: $request"
#       puts $params
#
#     }
#   }
# }

set PACKET [json typed [dict create \
  query [dict create \
    query $QUERY
  ] \
  variables [dict create \
    resolve ""
  ]
]]

namespace eval graphql {}
namespace eval ::graphql::parse {}

namespace eval ::graphql::regexp {
  variable graphql_re {(?xi) # this is the _expanded_ syntax
    ^\s*
    (?:  # Capture the first value (query|mutation) -> $type
         # if this value is not defined, query is expected.
      ([^\s\(\{]*)
      (?:(?!\()\s*)?
    )?
    (?:          # A query/mutation may optionally define a name
      (?!\()
      ([^\s\(\{]*)
    )?
    (?:\(([^\)]*)\))? # Capture the values within the variables scope
    \s*
    (?:{\s*(.*)\s*})
    $
  }

  # The start of the parsing, we capture the next value in the body
  # which starts the process of capturing downwards.
  variable graphql_body_re {(?xi)
    ^\s*
    (?!\})
    ([^\s\(\{:]*)  # capture the name of the query
    (?:        # optionally may define a name and fn mapping
      (?=\s*:)
      \s*:         # if a colon, then we need the fn name next
      \s*
      (?:
        ((?:
          (?=\[)      # WARNING: Breaking Schema Syntax Here for Tcl specific sugar
          \[[^\]]*\]  # allow passing tcl calls directly as a sugaring to GraphQL
                      # when providing a name (name: [myProc arg arg])
        ) |
        (?:
          [^\s\(\{]* # capture the name of the fn
        ))
      )
    )?
    \s*
    (?:\(([^\)]*)\))? # optionally capture var definitions
    \s*
    (.*)  # grab the rest of the request
    $
  }

  variable graphql_next_query_re {(?xi)
    ^\s*(?:\{\s*)?
    (?!\})
    ([^\s\(\{:]*)  # capture the name of the query
    (?:        # optionally may define a name and fn mapping
      (?=\s*:)
      \s*:         # if a colon, then we need the fn name next
      \s*
      (?:
        ((?:
          (?=\[)      # WARNING: Breaking Schema Syntax Here for Tcl specific sugar
          \[[^\]]*\] # allow passing tcl calls directly as a sugaring to GraphQL
        ) |
        (?:
          [^\s\(\{]* # capture the name of the fn
        ))
      )
    )?
    (?:
      (?=\s*\()    # check if we have arg declarations
      \s*
      \(
        ([^\)]*)   # grab the arg values
      \)
    )?
    (?:           # directives @include(if: $boolean) / @skip(if: $boolean)
      (?=\s*@)
      \s*(@[^\(]*\([^\)]*\)) # capture the full directive to be parsed
                             # we only capture the full directive and
                             # run another query to get the fragments
                             # if needed.
    )?
    (?:
      (?=\s*\{)    # this is a object type, capture the rest so we know
                   # to continue parsing
      \s*\{
      (.*)
      $
    )?
    \s*           # this will only have a value if we are done parsing
    (.*)          # this value, otherwise its sibling will.
  }

  variable graphql_directive_re {(?xi)
    ^@
    ([^\s\(]*)  # the directive type - currently "include" or "skip"
    \s*\(if:\s*
    ([^\s\)]*)  # capture the variable to check against
    \s*\)
    $
  }
}

proc ::graphql::parse data {
  set parsed [dict create]
  set definitions {}
  set type {}

  if {[dict exists $data variables]} {
    dict set parsed variables [dict get $data variables]
  }

  if {[dict exists $data query query]} {
    set query [string trim [dict get $data query query]]
  }

  regexp -- $regexp::graphql_re $query \
    -> type name definitions body

  dict set parsed type $type

  dict set parsed name $name

  set body [string trim $body]

  if {$definitions ne {}} {
    ::graphql::parse::definitions $definitions
  }

  ::graphql::parse::body $body

  return $parsed
}

proc ::graphql::parse::definitions definitions {
  upvar 1 parsed parsed

  foreach {var type} $definitions {
    if {$var eq "="} {
      set default [string trim $type " \"'\{\}"]
      # we are defining a default value to the previous variable
      if {![dict exists $parsed variables $lastParsedVar]} {
        dict set parsed variables $lastParsedVar $default
      }
      dict set parsed definitions $lastParsedVar default $default
      continue
    }

    set var [string trimright $var :]
    set var [string trimleft $var \$]

    if {[string match "*!" $type]} {
      set type [string trimright $type !]
      set required true
      if {![dict exists $parsed variables $var]} {
        tailcall return \
          -code error \
          -errorCode [list GRAPHQL PARSE VAR_NOT_DEFINED] \
          " variable $var is required but it was not provided within the request"
      }
    } else {
      set required false
    }

    if {[string index $type 0] eq "\["} {
      set isArray true
      set type [string range $type 1 end-1]
    } else {
      set isArray false
    }

    if {[dict exists $parsed variables $var]} {
      set varValue [dict get $parsed variables $var]
    } else {
      unset -nocomplain varValue
    }

    set type [string tolower $type]

    switch -- $type {
      float {
        set type double
        set checkType true
      }
      boolean {
        set checkType true
      }
      int {
        set type integer
        set checkType true
      }
      default {
        set checkType false
      }
    }

    if {$checkType && [info exists varValue]} {
      if {$isArray} {
        set i 0
        foreach elval $varValue {
          if {![string is $type -strict $elval]} {
            tailcall return \
              -code error \
              -errorCode [list GRAPHQL PARSE VAR_INVALID_TYPE IN_ARRAY] \
              " variable $var element $i should be ${type} but received: \"$elval\" while checking \"Array<${varValue}>\""
          }
          incr i
        }
      } elseif {![string is $type -strict $varValue]} {
        tailcall return \
          -code error \
          -errorCode [list GRAPHQL PARSE VAR_INVALID_TYPE IN_ARRAY] \
          " variable $var should be type \"${type}\" but received: \"$varValue\""
      }
    }

    set lastParsedVar $var

    dict set parsed definitions $var [dict create \
      type     [string tolower $type] \
      required $required
    ]
  }
}

proc ::graphql::parse::arg arg {
  upvar 1 parsed parsed
  if {[dict exists $parsed variables]} {
    set variables [dict get $parsed variables]
  }
  if {[string index $arg 0] eq "\$"} {
    set name [string range $arg 1 end]
    if {[dict exists $variables $name]} {
      set arg [dict get $variables $name]
    } else {
      # our parsing should have already given an error if it detected
      # this value shoudl be defined - we will simply set it to {}
      set arg {}
      #return -code error " variable $name not found for arg $arg"
    }
  }
  return $arg
}

proc ::graphql::parse::fnargs fnargs {
  upvar 1 parsed parsed
  set data [dict create]

  # set argName  {}
  # set argValue {}
  foreach arg $fnargs {
    set arg [string trim $arg]
    if {$arg eq ":"} {
      continue
    }
    if {[info exists argValue]} {
      # Once defined, we can set the value and unset our vars
      dict set data [arg $argName] [arg $argValue]
      unset argName
      unset argValue
    }
    if {![info exists argName]} {
      set colonIdx [string first : $arg]
      if {$colonIdx != -1} {
        if {[string index $arg end] eq ":"} {
          set argName [string trimright $arg :]
        } else {
          lassign [split $arg :] argName argValue
        }
      } else {
        # this is probably not right?
        set argName $arg
      }
    } else {
      set argValue $arg
    }
  }

  if {[info exists argName] && [info exists argValue]} {
    dict set data [arg $argName] [arg $argValue]
  }

  return $data
}

proc ::graphql::parse::directive directive {
  upvar 1 parsed parsed

  if {[dict exists $parsed variables]} {
    set variables [dict get $parsed variables]
  } else {
    set variables [dict create]
  }

  regexp -- $::graphql::regexp::graphql_directive_re $directive \
    -> type var

  if {[string index $var 0] eq "\$"} {
    set name [string range $var 1 end]
    if {[dict exists $variables $name]} {
      set val [dict get $variables $name]
    }
  } else {
    set val $var
  }

  switch -nocase -- $type {
    include {
      if {![info exists val] || ![string is true -strict $val]} {
        return false
      }
    }
    skip {
      if {[info exists val] && [string is true -strict $val]} {
        return false
      }
    }
    default {
      return tailcall \
        -code error \
        -errorCode [list GRAPHQL BAD_DIRECTIVE] \
        " provided a directive of type $type ($directive).  This is not supported by the GraphQL Syntax."
    }
  }

  return true

}

proc ::graphql::parse::body remaining {
  upvar 1 parsed parsed
  # set lvl 1

  while {$remaining ne {}} {
    set props [list]

    regexp -- $::graphql::regexp::graphql_body_re $remaining \
      -> name fn fnargs remaining

    if {![info exists name] || $name eq {}} {
      break
    }

    if {[string index $name 0] eq "\$"} {
      if {[dict exists $parsed variables [string range $name 1 end]]} {
        set name [dict get $parsed variables [string range $name 1 end]]
      }
    }

    if {$fn eq {}} {
      set fn $name
    }

    if {$fnargs ne {}} {
      set fnargs [::graphql::parse::fnargs $fnargs]
    }

    set remaining [nextType $remaining]

    dict lappend parsed requests $name [dict create \
      name  $name \
      fn    $fn \
      args  $fnargs \
      props $props
    ]

    set remaining [string trimleft $remaining "\}\n "]
  }
}

proc ::graphql::parse::nextType remaining {
  upvar 1 props pprops
  # upvar 1 lvl plvl
  upvar 1 parsed parsed
  # set lvl [expr {$plvl + 1}]

  while {[string index $remaining 0] ne "\}" && $remaining ne {}} {
    unset -nocomplain name
    set skip false
    set props [list]

    regexp -- $::graphql::regexp::graphql_next_query_re $remaining \
      -> name fn fnargs directive schema remaining

    if {![info exists name] || $name eq {}} {
      break
    }

    if {[string index $name 0] eq "\$"} {
      if {[dict exists $parsed variables [string range $name 1 end]]} {
        set name [dict get $parsed variables [string range $name 1 end]]
      }
    }

    if {$directive ne {}} {
      # directive will tell us whether or not we should be
      # including the value.
      if {![::graphql::parse::directive $directive]} {
        set skip true
      }
    }

    set prop [dict create name $name]

    if {[info exists fnargs] && $fnargs ne {}} {
      set fnargs [::graphql::parse::fnargs $fnargs]
      dict set prop args $fnargs
    }

    if {[info exists schema]} {
      set schema [string trim $schema]
      if {$schema ne {}} {
        if {$fn eq {}} {
          set fn $name
        }
        dict set prop fn $fn
        set schema [nextType $schema]
        set schema [string trim $schema]
        # remove the trailing curly bracket
        if {[string index $schema 0] eq "\}"} {
          set remaining [string range $schema 1 end]
        } else {
          set remaining $schema
        }
      }
    }

    if {[string is false $skip]} {
      if {[llength $props] > 0} {
        dict set prop props $props
      }
      lappend pprops $prop
    }

    set remaining [string trim $remaining]
  }

  # At this point, $schema will have content if we need to continue
  # parsing this type, otherwise it will be within remaining
  return $remaining
}


# proc printProp prop {
#   upvar 1 lvl plvl
#   set lvl [expr { $plvl + 1 }]
#   set prefix [string repeat " " $lvl]
#   puts "$prefix -- PROP -- [dict get $prop name]"
#   if {[dict exists $prop args]} {
#     puts "$prefix Args: [dict get $prop args]"
#   }
#   if {[dict exists $prop fnargs]} {
#     puts "$prefix FN Args: [dict get $prop fnargs]"
#   }
#   if {[dict exists $prop props]} {
#     puts "$prefix - Total Props [llength [dict get $prop props]]"
#     foreach cprop [dict get $prop props] {
#       printProp $cprop
#     }
#   }
# }
#
# proc print {} {
#   set lvl 0
#   foreach {k v} $::result {
#     switch -- $k {
#       requests {
#         foreach {query schema} $v {
#           puts "
#             --- QUERY $query ---
#           "
#           printProp $schema
#         }
#       }
#       default {
#         puts "-$k -> $v"
#       }
#     }
#   }
#   puts "
#     Time to Parse: [expr {$::stop - $::start}] microseconds
#   "
# }
#
# proc parse {} {
#   set data [json get $::PACKET]
#   set ::start [clock microseconds]
#   set ::result [::graphql::parse $data]
#   set ::stop [clock microseconds]
#   print
# }
