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
  set config [dict merge $CONFIG $args]
  set sessionID [my nextid]
  tailcall ::net::class::Session create \
    ::net::sessions::$sessionID [self] $url $config
}

::oo::define ::net::class::Net method nextid {} {
  return [self]#[incr I]
}

::oo::define ::net::class::Net method template {name args} {
  if {[llength $args] == 1} {
    # since no config values have a single element, this is
    # either invalid or it was sent as a dict rather than
    # as args, unpack the element...
    lassign $args args
  }
  tailcall [self class] create $name $args
}

::oo::define ::net::class::Net method encode {data} {
  tailcall ::net::urlencode $data
}

::oo::define ::net::class::Net method decode {data} {
  tailcall ::net::urldecode $data
}
