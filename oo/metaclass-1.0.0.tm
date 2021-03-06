
namespace eval ::oo::metaclass {
  variable i 0

  variable Build_Prefix_Meta {
    superclass ::oo::metaclass
  }
}

proc ::oo::metaclass::construct {} {uplevel 1 {
  namespace unknown [list ::oo::metaclass::unknown [info object class [self]]]
  namespace path [list \
    [[info object class [self]] namespace] \
    {*}[namespace qualifiers [info object class [self]]] \
    [[info object class [info object class [self]]] namespace] \
    {*}[namespace path]
  ]
}}

proc ::oo::metaclass::unknown {self what args} {
  if { $what in [info object methods $self -all] } {
    tailcall $self $what {*}$args
  } elseif { [list ::oo::define::$what] in [info commands ::oo::define::*] } {
    tailcall ::oo::define $self $what {*}$args
  } else { tailcall ::unknown $what {*}$args }
}

proc ::oo::metaclass::define { metaclass what args } {
  set metaclass [uplevel 1 [list namespace which $metaclass]]
  if { "::oo::metaclass" ni [info class superclasses [info object class $metaclass]] } {
    # this is not a metaclass
    tailcall ::oo::define $metaclass $what {*}$args
  }
  switch -- $what {
    constructor {
      lassign $args argnames body
      tailcall ::oo::define $metaclass constructor $argnames [format {
        %s ; %s } ::oo::metaclass::construct $body
      ]
    }
    default {
      tailcall ::oo::define $metaclass $what {*}$args
    }
  }
}

::oo::class create ::oo::metaclass {

  superclass ::oo::class

  # Creation of a new metaclass
  self method create {name definition args} {
    tailcall my createWithNamespace $name ${name} $definition {*}$args
  }

  constructor {{script {}}} {
    # We temporarily override [variable] so that we can define the class
    # variables.  We then remove it later so that class procs can still
    # call variable without causing issues.
    proc variable args { ::oo::define [uplevel 1 {self}] variable {*}$args }
    namespace unknown [list ::oo::metaclass::unknown [self]]
    if { [info object class [self]] ne "::oo::metaclass" } {
      namespace path [list \
        [namespace current] \
        [info object class [self]] \
        {*}[namespace path] \
        [uplevel 1 { namespace current }]
      ]
      # We need a constructor defined, if one is defined by the user then
      # it will be overwritten.
      try {constructor args {}}
      try $script[unset script]
    } else {
      namespace path [list {*}[namespace path] [uplevel 1 { namespace current }]]
      try [format \
        { %s ; %s } \
        $::oo::metaclass::Build_Prefix_Meta $script
      ][unset script]
    }
    rename variable {}
  }

  self method namespace {} { namespace current }

}

::oo::define ::oo::metaclass method constructor {argnames body args} {
  tailcall ::oo::define [self] constructor $argnames [format {
    %s ; %s } ::oo::metaclass::construct $body
  ]
}

::oo::define ::oo::metaclass method namespace {} { namespace current }

::oo::define ::oo::metaclass method scope ns {
  ::variable scope $ns
  namespace eval $ns {}
}

::oo::define ::oo::metaclass method create {name args} {
  ::variable scope
  if { [info object class [self]] eq "::oo::metaclass" } {
    if { [info exists scope] } {
      set path ${scope}::$name
    } else {
      set path [uplevel 1 {namespace current}]::$name }
    if { [info commands ${path}::my] ne {} } {
      set path ${path}[incr ::oo::metaclass::i]
    }
    tailcall my createWithNamespace $name $path {*}$args
  } else {
    set id [namespace tail $name]
    if { [info exists scope] } {
      set path ${scope}::$id
    } else { set path [namespace current]::$id }
    if { [info commands ${path}::my] ne {} } {
      set path ${path}[incr ::oo::metaclass::i]
    }
    tailcall my createWithNamespace \
      $name \
      $path {*}$args
  }
}

::oo::define ::oo::metaclass method new {args} {
  set i [ incr ::oo::metaclass::i ]
  tailcall my createWithNamespace \
    Obj$i \
    [namespace current]::[namespace tail [self]]Obj$i {*}$args
}

::oo::define ::oo::metaclass method unknown {method args} {
  switch -- $method {
    namespace { return [namespace current] }
    default   { ::unknown $method {*}$args }
  }
  return
}
