proc ::const {name value} {
	uplevel 1 [list set $name $value]
	uplevel 1 [list trace var $name w "set $name [list $value];#" ]
}