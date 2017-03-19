# Provides a protected-valias which allows us to alias a value to a given variable
# and allow the aliased variable to be read, but writing it will have no effect unless
# written from the original side.
# 
# If the alias value is written on, we modify it back to an empty string immediately 
# so a value can not exist on it.
proc protected_valias {alias source} {
  if { ! [string match ::* $alias] } {
    set qa  [uplevel 1 { namespace current }]::$alias
  } else { set qa $alias }
  if { ! [string match ::* $source] } {
    set qs  [uplevel 1 { namespace current }]::$source
  } else { set qs $source }
  uplevel 1 [list trace add v $qa read [list [namespace current]::readonlyread $qa $qs] ]
  uplevel 1 [list trace add v $qa write "set $qa {};#"]
}

proc readonlyread { qa qs varread args } {
  upvar 1 $varread value
  upvar 0 $qs source
  set value $source
  after cancel [list set $qa {}]
  after 0 [list set $qa {}]
}
