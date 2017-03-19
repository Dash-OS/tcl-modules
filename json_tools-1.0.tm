
# Require the rl_json extension
package require rl_json

# Load yajltcl if it exists, yajl is still the best
# way to generate dynamic json
catch { package require yajltcl }

# Taken from the json tcllib package for validation
namespace eval ::json {
  # Regular expression for tokenizing a JSON text (cf. http://json.org/)
  # tokens consisting of a single character
  ::variable singleCharTokens  { "{" "}" ":" "\\[" "\\]" "," }
  ::variable singleCharTokenRE "\[[::join $singleCharTokens {}]\]"
  # quoted string tokens
  ::variable escapableREs    { "[\\\"\\\\/bfnrt]" "u[[:xdigit:]]{4}" "." }
  ::variable escapedCharRE   "\\\\(?:[::join $escapableREs |])"
  ::variable unescapedCharRE {[^\\\"]}
  ::variable stringRE        "\"(?:$escapedCharRE|$unescapedCharRE)*\""
  # as above, for validation
  ::variable escapableREsv  { "[\\\"\\\\/bfnrt]" "u[[:xdigit:]]{4}" }
  ::variable escapedCharREv "\\\\(?:[::join $escapableREsv |])"
  ::variable stringREv      "\"(?:$escapedCharREv|$unescapedCharRE)*\""
  # (unquoted) words
  ::variable wordTokens  { "true" "false" "null" }
  ::variable wordTokenRE [::join $wordTokens "|"]
  # number tokens
  # negative lookahead (?!0)[[:digit:]]+ might be more elegant, but
  # would slow down tokenizing by a factor of up to 3!
  ::variable positiveRE    {[1-9][[:digit:]]*}
  ::variable cardinalRE    "-?(?:$positiveRE|0)"
  ::variable fractionRE    {[.][[:digit:]]+}
  ::variable exponentialRE {[eE][+-]?[[:digit:]]+}
  ::variable numberRE      "${cardinalRE}(?:$fractionRE)?(?:$exponentialRE)?"
  # JSON token, and validation
  ::variable tokenRE  "$singleCharTokenRE|$stringRE|$wordTokenRE|$numberRE"
  ::variable tokenREv "$singleCharTokenRE|$stringREv|$wordTokenRE|$numberRE"
  # 0..n white space characters
  ::variable whiteSpaceRE {[[:space:]]*}
  # Regular expression for validating a JSON text
  ::variable validJsonRE "^(?:${whiteSpaceRE}(?:$tokenREv))*${whiteSpaceRE}$"
  # 
  ::namespace ensemble create -unknown [::list ::json::unknown]
  ::namespace export {[a-z]*}
}


# tailcall the native ::rl_json::json commands into the json namespace
# since we cant just import them since ::rl_json::json is a command rather
# than a namespace.
proc ::json::rl        args { ::tailcall ::rl_json::json {*}$args           }
proc ::json::get       args { ::tailcall ::rl_json::json get       {*}$args }
proc ::json::set       args { ::tailcall ::rl_json::json set       {*}$args }
proc ::json::new       args { ::tailcall ::rl_json::json new       {*}$args }
proc ::json::json2dict args { ::tailcall ::rl_json::json get       {*}$args }
proc ::json::get_typed args { ::tailcall ::rl_json::json get_typed {*}$args }
proc ::json::type      args { ::tailcall ::rl_json::json type      {*}$args }
proc ::json::template  args { ::tailcall ::rl_json::json template  {*}$args }
proc ::json::normalize args { ::tailcall ::rl_json::json normalize {*}$args }
proc ::json::unset     args { ::tailcall ::rl_json::json unset     {*}$args }
proc ::json::extract   args { ::tailcall ::rl_json::json extract   {*}$args }
proc ::json::foreach   args { ::tailcall ::rl_json::json foreach   {*}$args }
proc ::json::lmap      args { ::tailcall ::rl_json::json lmap      {*}$args }

# Extends the native rl_json exists to handle the quirk it has in handling
# of an empty string ({}).  Since a JSON object is valid when it is an empty
# but properly formatted json object, exists will not throw an error with this
# workaround and will perform as expected (returning false since nothing exists)
proc ::json::exists { j args } {
  ::switch -- $j {
    {} - {{}} { ::return 0 } default {
      ::if { ! [ validate $j ] } { ::return 0 }
      ::return [ rl exists $j {*}$args ]
    }
  }
}

# Attempt to get the json value (returned as a dict) of the path.  If the
# path does not exist, returns {} rather than an error.
proc ::json::get?      args {
  ::if { [ exists {*}$args ] } {
    ::tailcall ::rl_json::json get {*}$args
  } else { ::return }
}

# Attempt to validate that a given value is a json object, returns bool
proc ::json::isjson   v { ::tailcall json validate $v }
proc ::json::validate v {
  ::variable validJsonRE
  ::return [ ::regexp -- $validJsonRE $v ]
}

# Push local variables into the json object while optionally transforming 
# the keys and/or default value should the value of the variable be {}

proc ::json::push { vname args } {
  ::if { $vname ne "->" } { ::upvar 1 $vname rj }
  ::if { ! [::info exists rj] || $rj eq {} } { ::set rj {{}} }
  ::foreach arg $args {
    ::set default [::lassign $arg variable name]
    ::upvar 1 $variable value
    ::if { [::info exists value] } {
      ::if { $name eq {} } { ::set name $variable }
      ::if { $value ne {} } {
        set rj $name [typed $value]
      } else { set rj $name [typed $default] }
    } else { ::throw error "$variable doesn't exist when trying to push $name into dict $var" }
  }
  ::return $rj
}

# Pull keys from the json object and create them as local variables in the
# callers scope.  Optionally provide the variables name, the default value 
# if the key was not found, and a path to the key.
# - Each element is either the name of the key or a list of $key $newName $default ...$path
#   where items in the list are optional.
proc ::json::pull { vname args } {
  ::upvar 1 $vname check
  ::if { [::info exists check] } {
    ::set j $check
  } else { ::set j $vname }
  ::set rj {{}}
  ::foreach v $args {
    ::set path [::lassign $v variable name default]
    ::if { $name eq {} } { ::set name $variable }
    ::upvar 1 $name value
    ::if { [exists $j {*}$path $variable] } {
      ::lassign [get_typed $j {*}$path $variable] value type
      ::set ex  [extract $j {*}$path $variable]
      set rj {*}$path $name $ex 
    } else { ::set value $default }
  }
  ::return $rj
}

# Similar to json pull, this allows you to provide a list as the first 
# argument to define the path you wish to operate from as a root.
# - Each argument may still specify the same arguments as in json pull
#   except that it will operate from the given main path.
proc ::json::pullFrom { vname args } {
  ::set mpath [::lassign $vname var]
  ::upvar 1 $var check
  ::if { [::info exists check] } { 
    ::set j $check
  } else { ::set j $var }
  ::set rj {{}}
  ::foreach v $args {
    ::set path [::lassign $v variable name default]
    ::if { $name eq {} } { ::set name $variable }
    ::upvar 1 $name value
    ::if { [ exists $j {*}$mpath $variable {*}$path ] } {
      ::set value [ get $j {*}$mpath $variable {*}$path ]
      set rj $name [extract $j {*}$mpath $variable {*}$path]
    } elseif { $default ne {} } {
      ::set value $default
      set rj $name $default
    } else { ::set value {} }
  }
  ::return $rj 
}

proc ::json::destruct args {
  
}

# Returns a new json object comprised of the given keys (if they existed in the
# original json object).  
proc ::json::pick { var args } {
  ::set rj {{}}
  ::foreach arg $args {
    ::set path [::lrange  $arg 0 end-1]
    ::set as   [::lindex  $arg end]
    ::if { [exists $var {*}$path $as] } {
      set rj $as [extract $var {*}$path $as]
    }
  }
  ::return $rj
}

# Iterates through a json object and attempts to retrieve one of its childs
# value ($key) and assigns that as the main keys value.
# { "foo": { "v" : 2 }, "bar": { "v": 3 } }
# withKey $j v == { "foo": 2, "bar": 3 }
proc ::json::withKey { var key } { 
  ::set rj {{}}
  rl foreach {k v} $var {
    ::if { [exists $v $key] } { set rj $k [extract $var $k $key] }
  }
  ::return $rj
}

# Modifies a given json object in place. The value can be a dict or an even
# number of arguments.
proc ::json::modify { vname args } {
  ::upvar 1 $vname rj
  ::if { ! [::info exists rj] } { ::set rj {{}} }
  ::if { [::llength $args] == 1 } { ::set args [::lindex $args 0] }
  ::dict for { k v } $args { set rj $k [typed $v] }
  ::return $rj
}

proc ::json::file2dict { file } {
  ::if { [::file isfile $file] } {
    ::set fh   [::open $file r]
    ::set data [::read -nonewline $fh]
    ::close $fh
    return [get $data]
  } else { ::throw error "File $file does not exist - cant convert from json to dict!" }
}

# Does a "best attempt" to discover and handle the value of an item and convert it
# to a json object or value.  Primitive support for properly built nested data 
# structures but should not be relied upon for that.  This is generally used to
# convert to a json value (example: hi -> "hi") and will first confirm the value
# is not already a json value (example: "hi" -> "hi")
# 
# This is a key ingredient to allowing many of the other functions to work.
proc ::json::typed {value args} {
  ::regexp {^value is a (.*?) with a refcount} \
    [::tcl::unsupported::representation $value] -> type
  ::if { "-map" ni $args && ! [ ::catch { type $value } err ] } { ::return $value }
  ::switch -glob -- $type {
    dict   { 
      ::set obj {}
      ::dict for { k v } $value {
        ::lappend obj $k [ typed $v -map ]  
      }
      ::if { "-map" in $args } { ::return "object $obj" }
      ::return [new object {*}$obj]
    }
    *array - list {
      ::set arr {}
      ::set i 0
      ::foreach v $value {
        ::set v [ typed $v -map ]
        ::if { $i == 0 && [::lindex $v 0] eq "array" && [::llength [::lindex $v 1]] == 2 } {
          ::set v [::lindex $v 1]
        }
        ::incr i
        ::lappend arr $v
      }
      ::if { "-map" in $args } { ::return "array $arr" }
      ::return [new array {*}$arr]
    }
    int - double  {
      ::if { "-map" in $args } { ::return "number [::expr {$value}]" }
      ::return [::expr {$value}]
    }
    boolean* { 
      ::if { "-map" in $args } { ::return "boolean [::expr {bool($value)}]" }
      ::return [::expr {bool($value)}] }
    *string - default {
      ::if {$value eq "null"} {
        ::return $value
      } elseif {[::string is entier -strict $value]} {
        ::if { "-map" in $args } { ::return "number [::expr {$value}]" }
        ::return [::expr {$value}]
      } elseif {[::string is double  -strict $value]} {
        ::if { "-map" in $args } { ::return "number [::expr {$value}]" }
        ::return [::expr {$value}]
      } elseif {[::string is boolean -strict $value]} {
        ::if { "-map" in $args } { ::return "boolean [::expr {bool($value)}]" }
        ::return [::expr {bool($value)}]
      }
    }
  }
  ::if { "-map" in $args } { ::return "string [new string $value]" }
  ::return [new string $value] 
}
  
proc ::json::object { what args } {
  ::set r {{}}
  ::switch -- $what {
    create {
      ::dict for {k v} $args {
        ::json set r $k [typed $v]
      }
    }
    lappend {
      ::set args [::lassign $args v k]
      ::upvar 1 $v j
      ::if { [info exists j] && [exists $j $k] } {
        ::lassign [get_typed $j $k] val type
        ::if { $type ne "array" } { ::throw error "You must use json object lappend on an array value" }
      }
      ::json set j $k [ typed [ ::lappend val {*}$args ] ]
      ::return $j
    }
  } 
  ::return $r
}

proc ::json::start {} {
  ::set json [yajl create #auto]
  return $json
}

proc ::json::done { json } {
  ::set body [$json get]
  $json delete
  ::return $body
}

# In-case new commands are added to rl_json we pass them through to the 
# rl_json procedure.  When handled with tailcall we should see a speed
# improvement of the handling (have yet to benchmark it).
proc ::json::unknown { ns cmd args } { 
  ::switch -- $cmd {
    default {
      ::return [ ::list ::rl_json::json $cmd ]
    }
  }
}