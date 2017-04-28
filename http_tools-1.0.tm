package require http
if { ! [catch { package require tls }] } {
  proc ::http::_ssl_configure args {
    set opts [lrange $args 0 end-2]
    set host [lindex $args end-1]
    set port [lindex $args end]
    ::tls::socket \
      -ssl3 0 \
      -ssl2 0 \
      -tls1 1 \
      -servername $host \
      {*}$opts $host $port
  }
  ::http::register https 443 ::http::_ssl_configure
}

proc ::http::_followRedirects {url args} {
  while 1 {
    set token [::http::geturl $url -validate 1]
    set ncode [::http::ncode $token]
    if { $ncode eq "404" } {
      throw error "URL Not found"
    }
    switch -glob $ncode {
      30[1237] {### redirect - see below ###}
      default  {::http::cleanup $token ; return $url}
    }
    upvar #0 $token state
    array set meta [set ${token}(meta)]
    ::http::cleanup $token
    if {![info exists meta(Location)]} {
      return $url
    }
    set url $meta(Location)
    unset meta
  }
  return $url
}

proc ::wget { url dest {retry 1} } {
  try {
    set chan [open $dest w]
    chan configure $chan -translation binary
    set url   [::http::_followRedirects $url]
    set token [::http::geturl $url -channel $chan -binary 1]
    if { [::http::ncode $token] != "200" } {
      ::http::cleanup $token
      if { $retry > 0 } { 
        after 500
        tailcall ::wget $url $dest [incr retry -1]
      }
      return 0
    }
    ::http::cleanup $token
    chan close $chan
  } on error {result} {
    if { [info exists token] } {
      ::http::cleanup $token 
    }
    if { $retry > 0 } {
      after 500
      tailcall ::wget $url $dest [incr retry -1]
    }
  }
  return 1
}

proc ::http::parse_token { token } {
  try {
    set response [dict create \
      code   [::http::ncode  $token] \
      status [::http::status $token] \
      data   [::http::data   $token]
    ]
  } on error {result options} {
    ::onError $result $options "While Parsing a Token"
  } finally { ::http::cleanup $token }
  return $response
}