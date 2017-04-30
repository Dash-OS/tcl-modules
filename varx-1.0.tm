package require ensembled

namespace eval ::varx { ensembled }

proc ::varx::variables args { ::foreach var $args { ::uplevel 1 [::list variable $var] } }

proc ::varx::define args { 
  ::foreach var $args {
    ::upvar 1 $var v
    ::if { ! [::info exists v] } { ::set v {} }
  }
  ::return $args
}

proc ::varx::sets args {
  ::foreach {var val} $args {
    ::upvar 1 $var ref 
    ::set ref $val
  }
  ::return $args
}

proc ::varx::switch args {
  ::set nocase 0; ::set next 0; ::set response {}
  
  ::while {$args ne {}} {
    set args [lassign $args arg]
    ::if { ! [::string equal [::string index $arg 0] -] } {
      ::if { ! [::info exists var] } { 
        ::set var $arg
      } else { 
        ::set args [::concat $arg $args]
        ::break 
      }
    } else {
      ::switch -- $arg {
        --      { ::break }
        -nocase { ::set nocase 1 }
        -upvar  { ::set upvar  1 }
      }
    }
  }
  
  ::if { [::info exists upvar] } {
    ::upvar 1 $var val
  } else { ::set val $var }
  
  ::foreach { pattern response } $args {
    ::if { $next } { 
      ::if { $response eq "-" } { ::continue } else { 
        ::set val $response
        ::return $response 
      }
    }
    ::if { $nocase ? [::string match -nocase $pattern $val] : [::string match $pattern $val] } {
      ::if { $response eq "-" } { ::set next 1 ; ::continue }
      ::set val $response
      ::return $response
    }
  }
  ::return
}

# proc myproc { new prev name } {
#   puts "$name | $prev --> $new" ; # v | 1 --> 2
# }
# set v 1
# ::varx trace v myproc
# set v 2
proc ::varx::trace { var callback {value {}} } {
  ::upvar 1 $var current
  ::if {![::info exists current]} {::set current $value}
  ::uplevel 1 [::list ::trace add variable $var write [ ::namespace code [::list traceback $callback $current] ]]
}

proc ::varx::traceback { callback prev var args } {
  ::upvar 1 $var value
  ::uplevel 1 [::list ::trace remove variable $var write [ ::namespace code [::list traceback $callback $prev  ] ]]
  ::uplevel 1 [::list ::trace add    variable $var write [ ::namespace code [::list traceback $callback $value ] ]]
  ::set a [::info args [::lindex $callback 0]]
  ::if { "args" in $a } {
    ::set args [::list $value $prev $var]
  } else {
    ::switch -- [::llength $a] {
      0 { ::set args {}                               }
      1 { ::set args [::list $value]                  }
      2 { ::set args [::list $value $prev]            }
      3 { ::set args [::list $value $prev $var]       }
      default { ::throw error {wrong # args: should be "", "value", "value prevValue", or "value prevValue varName"} }
    }
  }
  ::uplevel #0 [::list try [list $callback {*}$args]]
}

proc ::varx::untrace { var } {
  ::upvar 1 $var $var
  ::set info [::trace info variable $var]
  ::if { $info eq {} } { ::return }
  ::uplevel 1 [::list ::trace remove variable $var {*}[::lindex $info 0]]
}


proc ::varx::pipe args {
  ::set cmds [::split $args |]
  ::foreach cmd $cmds {
    ::set cmd [::string trim    $cmd]
    ::set s   [::string last -> $cmd]
    ::if { $s != -1 } {
      ::upvar 1 ___setter setter
      ::set setter [ ::string trim [ ::string range $cmd $s+2 end  ] ]
      ::set cmd    [ ::string trim [ ::string range $cmd 0    $s-1 ] ]
      ::if { [::llength $cmd] == 1 } { ::set cmd [::lindex $cmd 0] }
      ::set cmd    [ ::list ::try  [ ::list ::set $setter [::namespace current]::$cmd ] ]
      ::uplevel 1 $cmd
      ::uplevel 1 { 
        ::set ${___setter} [::try [::set ${___setter}] ] 
        ::unset ___setter
      }
    } else {
      ::if { [::llength $cmd] == 1 } { ::set cmd [::lindex $cmd 0] }
      ::uplevel 1 [ ::list ::try [::namespace current]::$cmd ]
    }
  }
}

proc ::varx::alias { var alias } { ::uplevel 1 [::list ::upvar 0 $var $alias] }

proc ::varx::empty { varName args } {
  ::upvar 1 $varName var
  ::tailcall ::if [::expr {![::info exists var] || $var eq {}}] {*}$args
}

proc ::varx::null {varName args} {
  ::upvar 1 $varName var
  ::tailcall ::if [::expr {![::info exists var]}] {*}$args
}

# ::varx true 0 {
#   puts "is false"
# } else {
#   puts "not false"
# }
proc ::varx::false {varName args} {
  ::upvar 1 $varName var
  ::tailcall ::if [::expr {[::info exists var] && [::string is false -strict $var]}] {*}$args
}

# ::varx true 1 {
#   puts "is true"
# } else {
#   puts "not true"
# }
proc ::varx::true {varName args} {
  ::upvar 1 $varName var
  ::tailcall ::if [::expr {[::info exists var] && [::string is true -strict $var]}] {*}$args
}

proc ::varx::is? {varName check} {
  ::upvar 1 $varName $varName
  ::switch -- $check {
    true  { return [::expr { [::info exists $varName] && [::string is true -strict [::set $varName]]}] }
    false { return [::expr { [::info exists $varName] && [::string is false -strict [::set $varName]]}] }
    null  { return [::info exists $varName] }
    empty { return [::expr { ! [::info exists $varName] || [::set $varName] eq {} }] }
  }
}

proc ::varx::is {varName checks args} {
  ::upvar 1 $varName $varName
  
}



