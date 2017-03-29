package require oo::metaclass

::oo::metaclass create ::module {
  
  method prop {name {value {}} } {
    my variable $name
    if { $value eq {} } { 
      return [set $name]
    } else {
      set $name $value
    }
  }

}
