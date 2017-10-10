if 0 {
  @ Net @
    | Provides the base properties for each
    | http session returned.
}
::oo::class create ::net::class::Net {
  variable CONFIG
  variable I

  constructor args {
    lassign $args CONFIG
    variable I 0
  }
}

::oo::define ::net::class::Net method call {url args} {
  # set ::START [clock microseconds]
  set config [dict merge $CONFIG $args]
  set sessionID [self]#[incr I]
  tailcall ::net::class::Session create \
    ::net::sessions::$sessionID $url $config
}

::oo::define ::net::class::Net method template {name config} {
  tailcall [self class] create $name $config
}
