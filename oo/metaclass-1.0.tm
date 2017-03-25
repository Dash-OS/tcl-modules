
namespace eval ::oo::metaclass {
  
  variable i 0
  
  variable Build_Prefix_Meta {
    superclass ::oo::metaclass
    proc variable {args} {
      foreach var $args { ::oo::define [uplevel 1 {self}] variable $var }
    }
  }
  
  variable Build_Constructor_Object {
    namespace unknown [list ::oo::metaclass::unknown [info object class [self]]]
    namespace path [list [namespace parent [namespace parent]] [namespace parent] {*}[namespace path]]
  }
  
  proc unknown {self what args} {
    if { [string equal [string index $what 0] *] } {
      uplevel 1 [list \
        [uplevel 1 {namespace current}]::my \
        @@RenderChild \
        [uplevel 1 [list namespace which [string range $what 1 end]]] \
        {*}$args
      ]
    } else {
      if { $what in [info object methods $self -all] } {
        tailcall $self $what {*}$args
      } elseif { [list ::oo::define::$what] in [info commands ::oo::define::*] } {
        tailcall ::oo::define $self $what {*}$args
      } else { tailcall ::unknown $what {*}$args }
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
    namespace unknown [list ::oo::metaclass::unknown [self]]
    if { [info object class [self]] ne "::oo::metaclass" } {
      namespace path [list [namespace current] [info object class [self]] {*}[namespace path] [uplevel 1 { namespace current }]]
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
  }
  
  method constructor {argnames body args} {
    puts "Constructor [self]"
    tailcall ::oo::define [self] constructor $argnames [format {
      %s ; %s } $::oo::metaclass::Build_Constructor_Object $body
    ]
  }
  
  method unknown {method args} {
    switch -- $method {
      namespace { return [namespace current] }
      default   { ::unknown $method {*}$args }
    }
  }
  
  method namespace {} { namespace current }
  
  method create {name args} {
    if { [info object class [self]] eq "::oo::metaclass" } {

      tailcall my createWithNamespace $name [namespace current]::${name}[incr ::oo::metaclass::i] {*}$args
    } else {
      tailcall my createWithNamespace \
        $name \
        [namespace current]::[namespace tail [self]][incr ::oo::metaclass::i] {*}$args
    }
	}
  
  method new {args} {
    set i [ incr ::oo::metaclass::i ]
    tailcall my createWithNamespace \
      Obj$i \
      [namespace current]::[namespace tail [self]]Obj$i {*}$args
  }
  
}