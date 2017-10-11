if 0 {
  @ ::net::polyfill @
    | This will replace the [http] package as built-in by providing aliases to
    | the commands it provides.

    An argument may be made that using [interp alias] or another alias method
    would be the best way to implement this.  Ideas are welcome if you believe
    it should be done this way.
}

namespace eval ::http {}

proc ::http::geturl {url args} {
  tailcall ::net call $url {*}$args
}

proc ::http::cleanup args {
  # no reason to not accept multiple sessions here
  # like the [net] package provides.  It is still
  # backwards compatible with the http packages method.
  foreach session $args {
    catch { $session destroy }
  }
}
