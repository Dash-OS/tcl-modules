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
  
  
  
  if { [::catch {::string cat}] } {
    proc cat args { ::join $args {} }
  }
  
  proc tocamel word {
    ::set buf ""
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
    ::regsub -all "\[ \t\n]+" $str { } newStr
    ::tailcall ::string trim $newStr
  }
  
  # round to the given number of decimals [string round 20 2] ; 20.00
  proc round { n {count 2} } { ::format %.${count}f $n }
  
  proc slugify str {
    ::set str [::string map { {?} {} {&} {=} {} {} {!} {} {.} {} {,} {} {$} {} {/} {} {#} {} {[} {} {]} {} } $str]
    ::tailcall ::string tolower [::string map { { } {-} } [::string compact $str]]
  }
  
  proc hasvars str {
    ::tailcall regexp {\$[^\s[:digit:]]{?[^\w]*?}?} $str
  }
  
  proc vars {str} {
    ::tailcall regexp -inline -all {\$\:?\:?{?[^\s[:digit:](?!:\{?[:digit:]\}?)]\w*\:?\:?\(?\w*\)?[^\s+\w\)]?}?} $str
  }
  
  proc varnames {str} {
    ::tailcall string map { {$} {} "\{" "" "\}" "" \\ {}} [string vars $str]
  }
}