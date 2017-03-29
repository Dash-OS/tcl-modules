
# What exists in list2 that does not exist in list1 ?
proc ldiff { list1 list2 } {
  set parse [ expr { [llength $list1] <= [llength $list2] ? "list1" : "list2" }]
  set l [set $parse]
  set result $list2
  foreach e $l {
    if { $parse eq "list1" } {
      set result [lremove $e $result]
    } elseif { $e in $list1 } {
      set result [lremove $e $result]
    }
  }
  return $result
}

proc lhas { l1 l2 } {
  if { [llength $l1] > [llength $l2] } { return 0 }
  foreach l $l1 {
    if { $l eq "*" } { continue }
    if { $l in $l2 } { continue }
    return 0
  }
  return 1
}

proc lremove {w l} {lsearch -all -inline -not -exact $l $w}

proc ltrim {l} {
  set new {}
  foreach item $l { lappend new [string trim $item] }
  return $new 
}

proc lunion {args} {
  tailcall lsort -unique [concat {*}$args]
}

proc unshift { v args } {
  tailcall try [format { lreverse [lassign [ lreverse {%s} ] %s] } $v $args]
}

proc lintersect {list1 list2} {
  set len1 [llength $list1]
  set len2 [llength $list2]
  if { $len1 < $len2 } {
    set l1 $list1
    set l2 $list2
  } else {
    set l2 $list1
    set l1 $list2
  }
  set r {}
  foreach l $l1 {
    if { $l in $l2 } { lappend r $l }
  }
  return $r
}

proc lwhere {varname list condition} {
  uplevel [list lmap $varname $list \
    "if [list $condition] {set [list $varname]} continue"
  ]
}

proc vlist lst { list [string trim [join [list {} {*}$lst] " $"]] $lst }
  
# turn a list of varnames into a dict of name/value pairs in the callers scope
proc vdict lst { tailcall subst [format [join [list {} {*}$lst] " %s $"] {*}$lst] }
