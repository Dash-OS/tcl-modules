package require extend::string

namespace eval ::state::parse::parser {}

variable ::state::parse::parser::SubstSetter 1

proc ::state::parse::parser::Substituter { __setters } {}

proc ::state::parse::parser::ParseItemOps ops {
  set i 	0
  set id  [lindex $ops end]
  set ops [lrange $ops 0 end-1]
  set ops [string tolower $ops]
  set isKey 0; set isRequired 0; set type {}
  foreach op $ops {
    incr i
    if { ! [string equal $type {}] } {throw error "\[parse-attribute\] Unknown Item Op $op - while parsing $id - $ops"}
    if {$i == 1} {
      switch -nocase -glob -- $op {
        opt*    { continue }
        req*    { set isRequired 1 ; continue }
        key     { set isKey      1 ; continue }
        ind*		{ set isIndex    1 ; continue }
        default { throw error "\[parse-attribute\] Each items first parameter must be \"key, required, index, or optional\" - $ops" }
      }
    }
    if { [string equal $op index] } { set isIndex 1 ; continue }
    set type $op
  }
  if {$type ni [::state::types]} { throw error "\[parse-attribute\] $type is an unknown State Type." }
  if {[string equal $id {}] || [string equal $type {}]} { throw error "\[parse-attribute\] ID or Type could not be parsed: $ops" }
  return [dict create \
    id         $id \
    type       $type \
    isRequired $isRequired \
    isKey      $isKey
  ]
}

proc ::state::parse::parser::ParseOpLine {} {
  upvar 1 item    item
  upvar 1 setters setters
  upvar 1 ops     ops
  upvar 1 params  params
  
  set item [split $item |]
  if {[llength $item] > 2} { throw error "Items May Only Define a Single Piped Parameter - ${item}" }
  
  set ops    [string trim [lindex $item 0]]
  set params [string trim [lindex $item 1]]
  
  if { $setters ne {} && [string hasvars $item] } {
    set hasVars 1
    set pVars [string hasvars $params]
    set oVars [string hasvars $ops]
  } else { set hasVars 0 }
  
  if { $hasVars } {
    if { [string is true $pVars] } {
      set p [list]
      foreach e $params {
        set e [string trim $e]
        expr { [string index $e 0] eq "\$"
          ? [lappend p {*}[dict get $setters [string range $e 1 end]]]
          : [lappend p $e]
        }
      }
      set params $p
    }
    if { [string is true $oVars] } {
      set o [list]
      foreach e $ops {
        set e [string trim $e]
        expr { [string index $e 0] eq "\$"
          ? [lappend o [dict get $setters [string range $e 1 end]]]
          : [lappend o $e]
        }
      }
      set ops $o
    }
  }

}

proc ::state::parse::parser::items {} {
  upvar 1 parsedDict	parsedDict
  upvar 1 data				items
  upvar 1 setters 		setters
  set items 		[string trim $items]
  set items 		[split $items \n\;]
  set itemsData [dict create \
    key {} required [list] items [dict create]
  ]
  set ids [list] ; set ops {} ; set params {}
  foreach item $items {
    ParseOpLine
    set config [ParseItemOps $ops]
    
    set id [dict get $config id]
    if {$id in $ids} { throw error "\[parse-attribute\] Each Item must have a unique ID: $id -- $item" }
    lappend ids $id
    dict set itemsData items $id id $id
    
    if { [dict get $config isKey] && [dict get $itemsData key] eq {} } {
      if { [dict get $itemsData key] eq {} } {
        dict set itemsData key $id
      } else {
        throw error "\[parse-attribute\] An item may only have one \"key\" value"
      }
      dict set itemsData items $id isKey 1
    }
    
    if { [dict get $config isRequired] } { 
      dict lappend itemsData required $id 
      dict set itemsData items $id isRequired 1
    }
    
    dict set itemsData items $id type [dict get $config type]
    dict set itemsData items $id params $params

  }
  set parsedDict [dict merge $parsedDict[set parsedDict ""] [dict create \
    ids      $ids \
    key      [dict get $itemsData key] \
    required [dict get $itemsData required] \
    items    [dict get $itemsData items]
  ]]
}

proc ::state::parse::parser::conditions {} {
  upvar 1 parsedDict	parsedDict
  upvar 1 setters 		setters
  upvar 1 data				conditions
  set conditions [string trim $conditions]
  set ors    [list]
  set active [list]
  set keys   [list]
  if {[string index $conditions 0] eq "\{"} {
    foreach conditionGroup $conditions {
      lappend ors [ConditionsGroup [string trim $conditionGroup]]
    }
  } else { lappend ors [ConditionsGroup $conditions] }
  dict set parsedDict keys   $keys
  dict set parsedDict active $active
  dict set parsedDict ors    $ors
  
  return
}

proc ::state::parse::parser::ConditionsGroup {conditions} {
  upvar 1 parsedDict	parsedDict
  upvar 1 setters 		setters
  upvar 1 active			active
  upvar 1 keys				keys
  set conditions  [split $conditions \n\;]
  set rules       [list]
  set activeRules [list]
  set activeKeys  [list]
  foreach item $conditions {
    ParseOpLine
    set ops [ParseConditionOps $ops]
    set key [dict get $ops key]
    switch -- $key {
      @entry {
        # A special value that refers to the key of the given state
        set localID [dict get $parsedDict localID]
        # We only substitute if @entry is not a key in this state that
        # the user created.
        if { "@entry" ni [::state items $localID] } {
          set key [::state key $localID]
          dict set ops key $key
        }
      }
    }
    if { $key ni $keys } { lappend keys $key }
    dict set ops params $params
    if { [dict get $ops isActive] } { 
      if { $key ni $activeKeys } { lappend activeKeys $key }
      dict unset ops isActive
      lappend activeRules $ops
    } else { 
      dict unset ops isActive
      lappend rules $ops 
    }
  }
  set rules [concat $activeRules $rules]
  lappend active $activeKeys
  return $rules
}

proc ::state::parse::parser::ParseConditionOps ops {
  set Modifiers  [ ::state::modifiers ]
  set ActiveKeys [ ::state::active ]
  set ops        [ lassign $ops key ]
  set query      [ string tolower [lindex $ops end] ]
  set mods       [ lrange $ops 0 end-1 ]
  set modifiers  [ dict create ]
  set modKeys    [ dict keys $Modifiers ]
  
  if { [string equal $modifiers {}] && $query in $modKeys } { set mods $query }
  if { $query ni [::state::queries] } {
    throw error "\[parse-attribute\] - $query is not a known query !"
  }
  foreach modifier $mods {
    if { [string equal $modifier {}] } { continue }
    if { $modifier ni $modKeys } {
      throw error "\[parse-attribute\]: Modifier not registered: $modifier"
    }
    if { [dict exists $Modifiers $modifier on] } {
      dict lappend modifiers [dict get $Modifiers $modifier on] [dict get $Modifiers $modifier evaluate]
    }
  }
  
  return [dict create \
    isActive  [expr { $query in $ActiveKeys }] \
    query     $query \
    evaluate  [ dict get [::state::query_schema $query] evaluate ] \
    modifiers $modifiers \
    key       $key
  ]
}

proc ::state::parse::parser::descriptions {{recursed 0}} {
  set recurse [list items]
  upvar 1 parsedDict	parsedDict
  upvar 1 data				descriptions
  if {$recursed} { 
    upvar 1 description descriptions 
    upvar 1 id _id
  }
  dict for {id description} $descriptions {
    if { $id in $recurse && !$recursed } {
      descriptions 1
    } elseif {$recursed} {
      dict set parsedDict descriptions ${_id} $id $description 	
    } else {
      dict set parsedDict descriptions $id $description
    }
  }
}

proc ::state::parse::parser::titles {} {
  upvar 1 parsedDict	parsedDict
  upvar 1 data				titles
  upvar 1 setters 		setters
  if { $titles eq {} } { return }
  if { $setters ne {} && [string hasvars $titles] } {
    set vars [string varnames $titles]
    foreach var $vars {
      set titles [string map  [list \$$var \{[dict get $setters $var]\}] $titles]
    }
  }
  dict set parsedDict titles $titles
}


proc ::state::parse::parser::attributes {} {
  upvar 1 parsedDict __parsedDict
  upvar 1 data       __attributes
  upvar 1 setters    __setters
  
  if {${__setters} ne {}} {
    set __opVars [string vars ${__attributes}]
  } else { set __opVars {} }
  set __attributes [split ${__attributes} \n\;]
  if {${__opVars} ne {}} {
    dict with __setters {}
  }
  foreach __attribute ${__attributes} {
    set __attribute 				[split ${__attribute} |]
    lassign ${__attribute}	__data	__params
    lassign ${__data} 			__key 	__attribute
    if {${__opVars} ne {}} {
      set __params		[subst ${__params}]
      set __key 			[subst ${__key}]
      set __attribute [subst ${__attribute}]
    }
    dict set __parsedDict attributes [string trim ${__key}] [string trim ${__attribute}] [string trim ${__params}]
  }
}

proc ::state::parse::parser::formatters {} {
  upvar 1 parsedDict __parsedDict
  upvar 1 data       __attributes
  upvar 1 setters    __setters

  set __attributes [split ${__attributes} \n\;]
  foreach __attribute ${__attributes} {
    set __attribute 				[split ${__attribute} |]
    lassign ${__attribute}	__data	__params
    lassign ${__data} 			__key 	__attribute
    dict lappend __parsedDict formatters [list [string trim ${__key}] [string trim ${__attribute}] [string trim ${__params}]]
  }
}


proc ::state::parse::parser::vendor {} {
  upvar 1 parsedDict  parsedDict
  upvar 1 setters		  setters
  upvar 1 data        data
  
  if { $data eq {} } { return }

  if { $setters ne {} && [string hasvars $data] } {
    foreach var [string varnames $data] {
      if { [dict exists $setters $var] } {
        set data [string map [list \$$var \{[dict get $setters $var]\}] $data]  
      }
    }
  }
  if { [dict exists $data ruleID] && ! [dict exists $data commandID] } {
    # change this to commandID
    dict set parsedDict commandID [dict get $data ruleID]
    dict unset data ruleID
  }
  if { $data ne {} } {
    dict set parsedDict vendor $data
  }
  
}

proc ::state::parse::parser::config {} {
  upvar 1 parsedDict	parsedDict
  upvar 1 data				data
  upvar 1 setters 		setters

  if { $setters ne {} && [string hasvars $data] } {
    foreach var [string varnames $data] {
      if { [dict exists $setters $var] } {
        set data [string map [list \$$var \{[dict get $setters $var]\}] $data]  
      }
      
    }
  }
  dict set parsedDict config $data
}

## TO DO 
#
# Many of these exist from a previous setup for the parse.
# They can be optimized in many ways, however they do work
# well and are fairly quick.
#
# Optimize these when possible!


proc ::state::parse::parser::middlewares {} {
  upvar 1 parsedDict parsedDict
  upvar 1 data data
  dict set parsedDict middlewares [list {*}$data]
}

proc ::state::parse::parser::id {} {
  upvar 1 parsedDict parsedDict
  upvar 1 data			 data
  upvar 1 setters    setters
  if { $setters ne {} && [string hasvars $data] } {
     foreach var [string varnames $data] {
      if { [dict exists $setters $var] } {
        set data [string map [list \$$var [dict get $setters $var]] $data]  
      }
    }
  }
  dict set parsedDict id $data
}

proc ::state::parse::parser::in {} {
  upvar 1 parsedDict	__parsedDict
  upvar 1 data				__in
  upvar 1 setters     __setters
  set __opVars [string vars ${__in}]
  if { ${__opVars} ne {} && ${__setters} ne {} } {
    dict with __setters {}
    set __in [subst ${__in}]
  }
  dict set __parsedDict in ${__in}
}

proc ::state::parse::parser::at {} {
  upvar 1 parsedDict	__parsedDict
  upvar 1 data				__at
  upvar 1 setters     __setters
  set __opVars [string vars ${__at}]
  if { ${__opVars} ne {} && ${__setters} ne {} } {
    dict with __setters {}
    set __at [subst ${__at}]
  }
  dict set __parsedDict at ${__at}
}

proc ::state::parse::parser::every {} {
  upvar 1 parsedDict	__parsedDict
  upvar 1 data				__every
  upvar 1 setters     __setters
  set __opVars [string vars ${__every}]
  if { ${__opVars} ne {} && ${__setters} ne {} } {
    dict with __setters {}
    set __every [subst ${__every}]
  }
  dict set __parsedDict every ${__every}
}

proc ::state::parse::parser::title {} {
  upvar 1 parsedDict	parsedDict
  upvar 1 data				data
  upvar 1 setters 		setters
  if { $setters ne {} && [string hasvars $data] } {
     foreach var [string varnames $data] {
      if { [dict exists $setters $var] } {
        set data [string map [list \$$var [dict get $setters $var]] $data]  
      }
    }
  }
  dict set parsedDict title $data
}

proc ::state::parse::parser::state {} {
  upvar 1 parsedDict	parsedDict
  upvar 1 data				state
  dict set parsedDict state $state
}

proc ::state::parse::parser::evaluate {} {
  upvar 1 parsedDict	parsedDict
  upvar 1 data				evaluate
  lassign $evaluate evalArgs evalScript

  dict set parsedDict evaluate [dict create \
    scriptArgs      $evalArgs \
    scriptQueryArgs {} \
    script          $evalScript
  ]
}

proc ::state::parse::parser::response {} {
  upvar 1 parsedDict	parsedDict
  upvar 1 data				response
  dict set parsedDict response $response
}

proc ::state::parse::parser::default {} {
  upvar 1 parsedDict	parsedDict
  upvar 1 data				default
  upvar 1 setters 		setters
  if { $setters ne {} && [string hasvars $default] } {
    set vars [string varnames $default]
    foreach var $vars {
      set default [string map  [list \$$var \{[dict get $setters $var]\}] $default]
    }
  }
  dict set parsedDict default $default
}

proc ::state::parse::parser::ScriptArgs {ScriptArgs modifier} {
  set queryArgs {}
  return
}

proc ::state::parse::parser::ValueGetter {modifier} {
  return
}

proc ::state::parse::parser::ItemGetter {modifier} {
  return
}