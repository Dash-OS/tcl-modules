namespace eval ::shortid { variable i 0; variable n 1 }

proc ::shortid::rand {min max} {
  expr { int(rand() * ($max - $min + 1) + $min)}
}

proc ::shortid::shuffle { list {max {}}} {
 set l1 {}; set l2 {}; set l3 {}; set l4 {}
 foreach le $list[set list {}] {
   if {rand()<.5} {
     if {rand()<.5} { lappend l1 $le } else { lappend l2 $le }
   } {
     if {rand()>.5} { lappend l3 $le } else { lappend l4 $le }
   }
   if {$max ne {} && [incr i] >= $max } { break }
 }
 return [concat $l1 $l2 $l3 $l4]
}

proc ::shortid::encode { str {type base64} } {
  return [string map { {=} {} } [binary encode $type $str]]
}

proc ::shortid::shuffle_string { str {max {}} } {
  join [shuffle [split $str {}] $max] {}
}

proc ::shortid::generate { {max_length 8} } {

  set i [incr [namespace current]::i]

  lassign [shuffle [list 1 2 3 4]] 1 2 3 4

  set clicks [clock clicks]
  set cmds   [string map { {=} {} } [binary encode base64 [join [shuffle [info commands] 20] {}]]]

  set cl [expr { [string length $cmds] - 5 }]
  set c1 [::shortid::rand $1 $cl]; set c2 [::shortid::rand $3 $cl]

  set uuid [string range [shuffle_string [format {%s%s%s} \
    [ incr i ] \
    [ string range $cmds $c1 [expr { $c1 + 8 }] ] \
    [ string range $cmds $c2 [expr { $c2 + 8 }] ]
  ] ] $1 [expr { $1 + [expr {round( $max_length / 2 )}] }]]

  switch --  $1 {
    1 { set op1 [incr [namespace current]::n]${i}$::tcl_platform(os)$::tcl_platform(osVersion) }
    2 { set op1 $::tcl_platform(machine)${i}$::tcl_platform(user)[incr [namespace current]::n] }
    3 { set op1 [string range $cmds 5 30][expr { int( rand() * [info cmdcount] + 1 ) }] }
    4 { set op1 $cmds }
  }

  switch -- $2 {
    1 { set op2 $::tcl_platform(os)[incr [namespace current]::n][pid] }
    2 { set op2 [incr [namespace current]::n]$::tcl_platform(machine)$::tcl_platform(user)${i} }
    3 { set op2 [string range $cmds 20 end][expr { int( rand() * [info cmdcount] + 1 ) }]}
    4 { set op2 $cmds }
  }

  lassign [shuffle [list 1 2 3 4]] 1 2 3 4

  binary scan [ format {%s%s} \
    [string range $op1 $1 [expr { $1 + 8 }]] [string range [encode $op2 uuencode] $2 [expr { $2 + 8 }]] \
  ] H* h1

  binary scan [ format {%s%s} \
    [string range $op2 $3 [expr { $3 + 8 }]] [string range [encode $op1 uuencode] $4 [expr { $4 + 8 }]] \
  ] h* h2

  append uuid [string range [shuffle_string [ format {%s%s%s%s} \
    $h1 $i [string toupper $h2] [string range $clicks 9 14] \
  ] ] 0 [ expr { $max_length - [string length $uuid] }]]

  return [string range $uuid 0 [expr { $max_length - 1 }]]

}

proc ::shortid { {max_length 8} } { tailcall ::shortid::generate $max_length }
