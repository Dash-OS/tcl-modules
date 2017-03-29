namespace eval ::state {}
namespace eval ::state::register {}
namespace eval ::state::register::registry {}

variable ::state::register::registry::middlewares [dict create]

proc ::state::middlewares {} {
  return $register::registry::middlewares
}

proc ::state::middleware { middleware } {
  return [dict get $register::registry::middlewares $middleware]
}

proc ::state::register::middleware { name middleware config { mixins {} } } {
  if { [dict exists $registry::middlewares $name] } {
    throw error "\[state\]: Middleware $name already exists" 
  } else {
    dict for { mixin_type mixin } $mixins {
      set mixin_class [::oo::class create ::state::mixins::${name}_${mixin_type} $mixin]
      switch -- $mixin_type {
        api {
          ::oo::define ::state::API mixin -append $mixin_class
          dict unset mixins api
        }
        default { dict set mixins $mixin_type $mixin_class }
      }
    }
    dict set registry::middlewares $name \
      [dict create \
        config [dict merge [dict create] $config] \
        middleware $middleware \
        mixins     $mixins
      ]
  }
}