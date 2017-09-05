if 0 {
  @ const @
    | Create a variable which can not be changed
  @example
  {
    const foo bar
    puts $foo ; ## bar
    set foo bax
    puts $foo ; ## bar
  }
}
proc ::const {name value} {
	uplevel 1 [list set $name $value]
	uplevel 1 [list trace var $name w "set $name [list $value];#"]
}
