package require extend

extend ::string {

  proc matchfirst { var nocase args } {
    ::if {$nocase ne "-nocase"} {
      ::set args [::list $nocase {*}$args]
      ::set nocase {}
    }
    ::set next 0
    ::dict for { match response } $args {
      ::set matches [::string match {*}$nocase $match $var]
      ::if {$matches || $next} {
        if { $response eq "-" } {
          ::set next 1
          ::continue
        } else {
          ::return $response
        }
      }
    }
    ::return
  }

  if { [::info command ::tcl::string::cat] eq {} } {
    proc cat args {
      ::return [::join $args {}]
    }
  }

  proc tocamel word {
    ::set buf {}
    ::set c 0
    ::set newWord false
    ::foreach char [::split $word {}] {
      ::if { $char eq { } } {
        ::set newWord true
      } else {
        ::if {$newWord} {
          ::append buf [::string toupper $char]
        } else {
          ::append buf [::string tolower $char]
        }
        ::set newWord false
      }
    }
    ::return $buf
  }

  proc compact str {
    ::regsub -all {[ \t\n]+} $str { } newStr
    ::return [::string trim $newStr]
  }

  # round to the given number of decimals [string round 20 2] ; 20.00
  proc round { n {count 2} } {
    ::return [::format %.${count}f $n]
  }

  proc slugify str {
    ::set str [::string map { {?} {} {&} {=} {} {} {!} {} {.} {} {,} {} {$} {} {/} {} {#} {} {[} {} {]} {} } $str]
    ::return [::string tolower \
      [::string map { { } {-} } [::string compact $str]]
    ]
  }

  proc hasvars str {
    ::return [::regexp {\$[^\s[:digit:]]{?[^\w]*?}?} $str]
  }

  proc vars {str} {
    ::return [::regexp -inline -all \
      {\$\:?\:?{?[^\s[:digit:](?!:\{?[:digit:]\}?)]\w*\:?\:?\(?\w*\)?[^\s+\w\)]?}?} \
      $str
    ]
  }

  proc varnames {str} {
    ::return [::string map { {$} {} "\{" "" "\}" "" \\ {}} \
      [::string vars $str]
    ]
  }

  # string startswith hello "hello, world"
  proc startswith {chars str args} {
    ::tailcall string match {*}$args ${chars}* $str
  }

  # string endswith world "hello, world"
  proc endswith {chars str args} {
    ::tailcall string match {*}$args *${chars} $str
  }

  # string includes "ello," "hello, world"
  proc includes {chars str} {
    ::tailcall string match *${chars}* $str
  }
}
