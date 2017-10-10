if 0 {
  @ NOT FUNCTIONAL @
  > This is not yet functional and should not be used.
}

# net - this is a replacement for the http package with an
#       emphasis on performance, reuseability, and efficiency.

# used for prop validation
# package require proptypes

namespace eval net {
  # export and ensemble all procs that start with a
  # lower case letter.
  # namespace ensemble create
  namespace export {[a-z]*}

  # What methods do we accept?
  variable METHODS [list \
    GET POST PUT PATCH HEAD OPTIONS DELETE CONNECT
  ]

  variable protocols

  # When init is called, it checks to see if these values
  # exist.  If they do it will not change their values.
  variable formMap

  # Holds default values that will be used when others have not been
  # defined by the user.  This can be modified by calling [http config]
  #
  # configurations are passed down through our session process.
  #
  # $::net::config
  # -> $Template::CONFIG
  #  -> $Session::CONFIG
  #    -> Transforms
  #
  # You can easily set the global defaults for all calls by calling
  # [net::config ...args], but be careful as it may affect others within
  # the script.
  #
  # Otherwise you may create a [net template $NAME ...TemplateConfig] then
  # $NAME call ...SessionConfig
  #
  # By default a template is created with no configuration and saved as
  # a command "net"
  variable config

  variable encodings [string tolower [encoding names]]

  variable validate_url_re {(?x)	# this is _expanded_ syntax
    ^
    (?: (\w+) : ) ?			# <protocol scheme>
    (?: //
        (?:
      (
          [^@/\#?]+		# <userinfo part of authority>
      ) @
        )?
        (				# <host part of authority>
      [^/:\#?]+ |		# host name or IPv4 address
      \[ [^/\#?]+ \]		# IPv6 address in square brackets
        )
        (?: : (\d+) )?		# <port part of authority>
    )?
    ( [/\?] [^\#]*)?		# <path> (including query)
    (?: \# (.*) )?			# <fragment>
    $
  }

  # Check for validity according to RFC 3986, Appendix A
  variable validate_user_re {(?xi)
    ^
    (?: [-\w.~!$&'()*+,;=:] | %[0-9a-f][0-9a-f] )+
    $
	}

  # Check for validity according to RFC 3986, Appendix A
	variable validate_path_re {(?xi)
    ^
    # Path part (already must start with / character)
    (?:	      [-\w.~!$&'()*+,;=:@/]  | %[0-9a-f][0-9a-f] )*
    # Query part (optional, permits ? characters)
    (?: \? (?: [-\w.~!$&'()*+,;=:@/?] | %[0-9a-f][0-9a-f] )* )?
    $
	}
}

namespace eval ::net::sessions {
  if 0 {
    > Summary
      | {::net::sessions} is where we will find each of our
      | TclOO Objects.  They can easily be listed by calling
      | [info commands ::net::sessions::*] and iterate through
      | them.
  }
}

namespace eval ::net::class {
  if 0 {
    > Summary
      | {::net::class} is where we find the classes and mixins
      | that are used to build the http session objects.
  }
}

package require net::classes::net
package require net::classes::session

proc ::net::init {} {
  variable formMap

  if {![info exists ::net::config]} {
    # -charset: {iso8859-1} This can be changed, but iso8859-1 is the RFC standard.
    # -strict: {true}       Force RFC 3986 strictness in geturl url verification?

    # Some of these values are not yet being used and/or may be removed.
    set ::net::config [dict create \
      -accept      */* \
      -proxyhost   {}  \
      -proxyport   {}  \
      -method      GET \
      -buffersize  65536 \
      -encoding    ascii \
      -charset     iso8859-1 \
      -strict      true \
      -version     1.1 \
      -urlencoding utf-8 \
      -keepalive   true \
      -headers     [list]
    ]

    # We need a useragent string of this style or various servers will refuse to
    # send us compressed content even when we ask for it. This follows the
    # de-facto layout of user-agent strings in current browsers.
    # safe interpreters do not have ::tcl_platform(os) or ::tcl_platform(osVersion).
    dict set ::net::config -useragent \
      [format {Mozilla/5.0 (%s) AppleWebKit/537.36 (KHTML, like Gecko) http/%s Tcl/%s} \
      [expr {[interp issafe]
        ? {(Windows NT 10.0; Win64; x64)}
        : "([string totitle $::tcl_platform(platform)]; U; $::tcl_platform(os) $::tcl_platform(osVersion))"
      }] \
      [package provide http] \
      [info patchlevel]
    ]
  }

  # taken from http package - not currently being used at all.
  # if {![info exists formMap]} {
  #   # Set up the map for quoting chars. RFC3986 Section 2.3 say percent
  #   # encode all except: "... percent-encoded octets in the ranges of
  #   # ALPHA (%41-%5A and %61-%7A), DIGIT (%30-%39), hyphen (%2D), period
  #   # (%2E), underscore (%5F), or tilde (%7E) should not be created by URI
  #   # producers ..."
  #   for {set i 0} {$i <= 256} {incr i} {
  #     set c [format %c $i]
  #     if {![string match {[-._~a-zA-Z0-9]} $c]} {
  #       dict set formMap $c %[format %.2X $i]
  #     }
  #   }
  #   # These are handled specially
  #   dict set formMap \n %0D%0A
  # }

  if {![info exists ::net::protocols]} {
    set ::net::protocols [dict create \
      http [list 80 socket]
    ]
  }

  foreach session [namespace children ::net::sessions] {
    # destroy each session that is still present, closing
    # any necessary sockets and cleaning up.
    $session destroy
  }

  if {[info command ::net] ne {}} {
    ::net destroy
  }

  ::net::class::Net create ::net

  return
}

proc ::net::geturl args {tailcall http call {*}$args}

proc ::net::validate {url {config {}}} {
  if {$config eq {}} {
    set config $::net::config
  }

  # TRANSFORM :: [request/validate]
  #  | This transform allows a template a chance to
  #  | modify the configuration which will be used to
  #  | setup our session.
  # if {[dict exists $config -transforms request validate start]} {
  #   try [dict get $config -transforms request validate start] on error {result} {
  #     tailcall return \
  #       -code error \
  #       -errorCode [list HTTP REQUEST_VALIDATE TRANSFORM]
  #   }
  # }

  if {[dict exists $config -query]} {
    dict set config -body [dict get $config -query]
    dict unset config -query
  }

  set method [string toupper [dict get $config -method]]

  set headers [dict get $config -headers]

  if {$method ni $::net::METHODS} {
    tailcall return \
      -code error \
      -errorCode [list HTTP VALIDATE INVALID_METHOD $method] \
      " unsupport method ${method}, should be one of $::net::METHODS"
  }

  dict set config -method $method

  if {![regexp -- $::net::validate_url_re $url -> proto user host port path]} {
    tailcall return \
      -code error \
      -errorCode [list HTTP VALIDATE INVALID_URL_FORMAT]
      " unsupported URL format: $url"
  }

  # Caller has to provide a host name; we do not have a "default host"
	# that would enable us to handle relative URLs.
  # NOTE: we don't check the hostname for validity here; if it's
	#       invalid, we'll simply fail to resolve it later on.
  set host [string trim $host {[]}]
  if {$host eq {}} {
    tailcall return \
      -code error \
      -errorCode [list HTTP VALIDATE INVALID_URL_FORMAT] \
      " invalid host or invalid format: $url"
  }

  if {$port ne {} && $port > 65535 } {
    tailcall return \
      -code error \
      -errorCode [list HTTP VALIDATE INVALID_PORT]
      " invalid port, ports should not be above 65535: $url"
  }

  # The user identification and resource identification parts of the URL can
  # have encoded characters in them; take care!
  if {$user ne {} && [dict get $config -strict] && ![regexp -- $::net::validate_user_re $user]} {
    if {[regexp -- {(?i)%(?![0-9a-f][0-9a-f]).?.?} $user bad]} {
      tailcall return \
        -code error \
        -errorCode [list HTTP VALIDATE ILLEGAL_CHARACTERS_IN_URL INVALID_USER_ENCODING] \
        " illegal encoding character usage \"$bad\" in URL user: $url"
    } else {
      tailcall return \
        -code error \
        -errorCode [list HTTP VALIDATE ILLEGAL_CHARACTERS_IN_USER] \
        " illegal characters in URL user: $url"
    }
  }

  if {$path ne {}} {
    # RFC 3986 allows empty paths (not even a /), but servers
  	# return 400 if the path in the HTTP request doesn't start
  	# with / , so add it here if needed.
    if {[string index $path 0] ne "/"} {
      set path /$path
    }
    if {[dict get $config -strict] && ![regexp -- $::net::validate_path_re $path]} {
      if {[regexp {(?i)%(?![0-9a-f][0-9a-f])..} $path bad]} {
		    tailcall return \
          -code error \
          -errorCode [list HTTP VALIDATE INVALID_FORMAT_URL_PATH] \
		      " illegal encoding character usage \"$bad\" in URL path: $path"
	    } else {
        tailcall return \
          -code error \
          -errorCode [list HTTP VALIDATE INVALID_FORMAT_URL_PATH] \
          " illegal characters in URL path: $path"
      }
    }
  } else {
    set path /
  }

  if {$proto eq {}} {
    # its time to default to https if registered
    if {[dict exists $::net::protocols https]} {
      set proto https
    } else {
      set proto http
    }
  }

  if {![dict exists $::net::protocols [string tolower $proto]]} {
    tailcall return -code error " invalid or unregistered protocol: $proto"
  }

  set protocol [dict get $::net::protocols [string tolower $proto]]

  # need this elsewhere
  if {[dict exists $config -proxyfilter]} {
    if {![catch {{*}[dict get $config -proxyfilter] $host} proxy]} {
      lassign $proxy phost pport
    } else {
      tailcall return \
        -code error \
        -errorCode [list HTTP VALIDATE PROXY_FILTER_ERROR] \
        " -proxyfilter value is not a callable command: [dict get $config -proxyfilter] | $proxy"
    }
  }

  set url ${proto}://

  if {$user ne {}} {
    append url $user @
  }

  if {$port != {}} {
    append host : $port
  }

  append url $host $path

  if {[info exists phost] && $phost ne {}} {
    set address [list $phost $pport]
  } else {
    if {$port eq {}} {
      set port [lindex $protocol 0]
    }
    set address [list $host $port]
  }

  if {"Host" ni $headers} {
    set headers [list Host $host {*}$headers[set headers {}]]
  }

  if {"Connection" ni $headers} {
    if {[dict get $config -keepalive]} {
      lappend headers Connection close
    } else {
      lappend headers Connection close
    }
  }

  if {"Accept" ni $headers} {
    lappend headers Accept [dict get $config -accept]
  }

  if {"Accept-Encoding" ni $headers} {
    lappend headers Accept-Encoding "gzip, deflate, compress"
  }

  if {"Accept-Charset" ni $headers} {
    lappend headers Accept-Charset "utf-8, iso-8859-1;q=0.5, windows-1251;q=0.25"
  }

  if {"User-Agent" ni $headers} {
    lappend headers User-Agent [dict get $config -useragent]
  }

  if {"Content-Length" in $headers} {
    # This is not allowed, remove any Content-Length headers currently
    # present.
    foreach idx [lreverse [lsearch -all $headers Content-Length]] {
      set headers [lreplace $headers[set headers {}] $idx [expr {$idx + 1}]]
    }
  }

  if {[dict exists $config -body]} {
    # If this is defined then we are expecting a compatible method
    # is being used.  We currently only check that the method is not
    # GET
    if {[dict get $config -method] eq "GET"} {
      tailcall return \
        -code error \
        -errorCode [list HTTP INVALID BODY_WITH_GET] \
        " illegally provided a body when conducting a GET request"
    }
    if {"Content-Type" ni $headers} {
      lappend headers Content-Type "application/json; charset=utf-8"
    }
    lappend headers Content-Length [string length [dict get $config -body]]
  } else {
    lappend headers Content-Length 0
  }

  dict set config -headers $headers

  # this is the object which our "end" transform may modify
  # before the session implements its values into its configuration.
  set request [dict create \
    HOST     $host \
    URL      $url \
    PROTOCOL $protocol \
    PATH     $path \
    CONFIG   $config \
    ADDRESS  $address
  ]

  # TRANSFORM :: [request/validate/end]
  #  | This transform has a chance of modifying the validated
  #  | request if needed.
  #  | This could result in malformed headers and other issues
  #  | use with care.
  # if {[dict exists $config -transforms request validate end]} {
  #   try [dict get $config -transforms request validate end] on error {result} {
  #     tailcall return \
  #       -code error \
  #       -errorCode [list HTTP REQUEST_VALIDATE TRANSFORM_END]
  #   }
  # }

  return $request
}

proc ::net::parse {response} {
  # parse a net response
  set headers [dict get $response headers]
  set state   [dict get $response state]
  set data    [dict get $response data]

  if {[dict get $state code] == 204} {
    return $response
  }

  if {[dict exists $headers content-length]} {
    # check the length of the data
    if {[string length $data] != [dict get $headers content-length]} {
      tailcall return \
        -code error \
        -errorCode [list HTTP PARSE_RESPONSE INVALID_CONTENT_LENGTH] \
        " the received content length ([string length $data]) did not match the expected length of [dict get $headers content-length]"
    }
  }

  # largely taken from rl_json
  # Reference > https://github.com/RubyLane/rl_http/blob/master/rl_http-1.4.tm
  foreach eheader {transfer-encoding content-encoding} {
    if {[dict exists $headers $eheader]} {
      foreach enc [lreverse [dict get $headers $eheader]] {
        switch -nocase -- $enc {
          chunked               { set data [ReadChunked $data] }
          base64                { set data [binary decode base64 $data] }
          gzip - x-gzip         { set data [zlib gunzip $data] }
          deflate               { set data [zilib inflate $data] }
          compress - x-compress { set data [zlib decompress $data] }
          identity - 8bit - 7bit - binary { # Nothing To Do # }
          default {
            tailcall return \
              -code error \
              -errorCode [list HTTP PARSE_REQUEST UNKNOWN_ENCODING] \
              " do not know how to handle encoding type $enc while parsing a request response"
          }
        }
      }
    }
  }

  if {[dict exists $headers content-type]} {
    set content_type	[lindex [dict get $response headers content-type] end]
			if {[regexp -nocase -- {^((?:text|application)/[^ ]+)(?:\scharset=\"?([^\"]+)\"?)?$} $content_type - mimetype charset]} {
        if {$charset eq {}} {
          switch -nocase -- $mimetype {
            application/json - text/json {
              set charset utf-8
            }
            application/xml - text/xml {
              # According to the RFC, text/xml should default to
							# US-ASCII, but this is widely regarded as stupid,
							# and US-ASCII is a subset of UTF-8 anyway.  Any
							# documents that fail because of an invalid UTF-8
							# encoding were broken anyway (they contained bytes
							# not legal for US-ASCII either)
							set charset utf-8
            }
            default {
              set charset identity
            }
          }
        }
        switch -nocase -- $charset {
					utf-8        { set data [encoding convertfrom utf-8     $data] }
					iso-8859-1   { set data [encoding convertfrom iso8859-1 $data] }
					windows-1252 { set data [encoding convertfrom cp1252    $data] }
					identity     { # Nothing To Do # }
					default {
						# Only broken servers will land here - we specified the set of encodings we support in the
						# request Accept-Encoding header
            tailcall return \
              -code error \
              -errorCode [list HTTP PARSE_REQUEST UNHANDLED_CHARSET $charset] \
              " the server responded with a charset that is not accepted: $charset"
					}
				}
      }
  }

  # TODO: A Transform will be made available here to transform
  #       responses.

  dict set response data $data

  return $response
}

proc ::net::ReadChunked data {
  set buffer {}
  while {1} {
    if {![regexp -- {^([0-9a-fA-F]+)(?:;([^\r\n]+))?\r\n(.*)$} $data - octets chunk_extensions_enc data]} {
      tailcall return \
        -code error \
        -errorCode [list HTTP PARSE_RESPONSE CHUNK_CORRUPTED] \
        " failed to parse request, invalid chunk body"
    }

    set chunk_extensions	[concat {*}[lmap e [split $chunk_extensions_enc ";"] {
      regexp -- {^([^=]+)(?:=(.*))?$} $e -> name value
      list $name $value
    }]]

    set octets	0x$octets

    if {$octets == 0} { break }

    append buffer	[string range $data 0 $octets-1]

    if {[string range $data $octets $octets+1] ne "\r\n"} {
      tailcall return \
        -code error \
        -errorCode [list HTTP PARSE_RESPONSE CHUNK_CORRUPT] \
        " attempted to parse a corrupt HTTP chunked body, format error"
    }

    set data [string range $data $octets+2 end]
  }

  set data [string trim $data]

  if {[string length $data] != 0} {
    # More Headers ?
    throw error "More Headers Error (FIXME)"
  }

  return $buffer
}

# number of open sessions or a list of all sessions if -inline is given
proc ::net::sessions args {
  if {"-inline" in $args} {
    tailcall info commands [namespace current]::sessions::*
  } else {
    tailcall llength [info commands [namespace current]::sessions::*]
  }
}

if 0 {
  @ ::net::register
    | Register a protocol (such as https)
  @arg proto {string}
  @arg port {[0-65535]}
  @arg command {cmdpath ...args?}
}
proc ::net::register {proto port command} {
    variable protocols
    dict set protocols $proto [list $port $command]
}

# http::unregister --
#     Unregisters URL protocol handler
#
# Changes:
#   - No longer throw error if unknown protocol is unregistered.
#
# Arguments:
#     proto	URL protocol prefix, e.g. https
# Results:
#     list of port and command that was unregistered.
proc ::net::unregister {proto} {
  set lower [string tolower $proto]
  if {[dict exists $::net::protocols $lower]} {
    set schema [dict get $::net::protocols $lower]
    dict unset ::net::protocols $lower
    return $schema
  }
}

# http::config --
#
#	See documentation for details.
#
# Arguments:
#	args		Options parsed by the procedure.
# Results:
#        TODO
proc ::net::config args {
  variable config
  if {[llength $args] == 0} {
    return $config
  } elseif {[llength $args] == 1} {
    lassign $args arg
    if {[dict exists $config $arg]} {
      return [dict get $config $arg]
    }
  } else {
    dict for {opt value} $args {
      if {![dict exists $config $opt]} {
        return -code error "Unknown option ${opt}, must be: [dict keys $config]"
      }
      dict set config $opt $value
    }
  }
}

proc ::net::urlencode args {
  rename ::net::urlencode {}
  package require net::utils::urlencode
  tailcall ::net::urlencode {*}$args
}

proc ::net::urldecode args {
  rename ::net::urlencode {}
  package require net::utils::urlencode
  tailcall ::net::urldecode {*}$args
}

::net::init

# net call http://my.dashos.net/v1/myip.json
# package require http
#
# proc testhttp {} {
#   set ::START [clock microseconds]
#   ::http::geturl http://my.dashos.net/v1/myip.json -command finishhttp
# }
#
# proc finishhttp {token} {
#   set data [::http::data $token]
#   set ::STOP [clock microseconds]
#   puts " $data | [expr {$::STOP - $::START}] microseconds"
# }
#
# after 3000 { set i 0 }
# vwait i
#
#
# http template POST {
#   -method POST
# }
#
# POST call http://www.google.com \
#   -body {{"one": "two"}}
#
# http call http://www.google.com \
#   -method POST \
#   -body {{"one": "two"}} \
#   -command [callback ::net::callback]

#
# A look at the planned -transforms syntax to allow modifying
# requests made by specific objects.  This should allow creating
# customized calls which have custom properties such as proxies,
# encryptions, parsing/formatting, etc.
#
# http template ::net::post \
#   -headers  [list Content-Type application/json] \
#   -method   POST \
#   -timeout  15000 \
#   -command  {http cleanup} \
#   -transforms {
#     request {
#       validate {
#         start {
#           # When defined, will be included right before we begin the
#           # validation process.
#           # local vars: url config
#
#         }
#         end {
#           # When defined, will be included right before returning the
#           # $request dict back to the session.  these values will then
#           # be used to configure the session and make the request.
#           #
#           # Be careful when using this transform.
#           # local vars: request
#           # note that there are many other local vars in
#           # scope, but the $request var is the only one
#           # that will be passed to the caller as our response.
#         }
#       }
#     }
#     socket {
#       opening {
#         # Right before the open socket command is sent.  You may modify
#         # the values, including the "$command" which will be called to
#         # open the socket using [{*}$command {*}$socketargs]
#       }
#       connected {
#         # Right after the socket channel has successfully connected
#         # and has reported its [chan event writable].
#       }
#       closing {
#
#       }
#       closed {
#
#       }
#     }
#     response {
#       complete {
#         # Allows modifying the response right before returns to the caller.
#         # modifying $data w
#       }
#     }
#   }
#
# # -query also would work
# http post \
#   -body    {{"foo": "bar"}}
#
# http package
# "75.84.148.45" | 359235 microseconds
# "75.84.148.45" | 372838 microseconds
# "75.84.148.45" | 384520 microseconds
# "75.84.148.45" | 406488 microseconds

# net
# "75.84.148.45" | 167590 microseconds
# "75.84.148.45" | 177536 microseconds
# "75.84.148.45" | 190034 microseconds
# "75.84.148.45" | 192529 microseconds

# net template POST -method POST -headers [list Content-Type application/json]
# POST -body {{"foo": "bar"}}
