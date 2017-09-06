package require ensembled
namespace eval redelay {ensembled}

::oo::class create ::redelay::mixin {
  constructor args {
    my variable __redelay_count
    set __redelay_count 0
    if { [self next] ne {} } {
      next {*}$args
    }
  }
  method redelay { {arg {}} } {
    if { $arg eq "reset" } {
      return [ my __redelay_reset ]
    } else {
      return [ my __redelay_tick {*}$arg ]
    }
  }
  method __redelay_reset {} {
    my variable __redelay_count
    set __redelay_count 0
  }
  method redelay_max max {
    my variable __redelay_max
    set __redelay_max $max
  }
  method __redelay_tick { {max {}} } {
    my variable __redelay_count
    my variable __redelay_max
    if { [info exists __redelay_max] && $max eq {} } {
      set max [set __redelay_max]
    } elseif { $max eq {} } {
      set max 30
    }
    set interval [expr { min( $max,(pow(2,[incr __redelay_count])-1)) * 1000 }]
    set delay    [expr { int( rand() * ( $interval - 1 + 1 ) + 1 ) + 1000 }]
    return $delay
  }
}

proc ::redelay::redelay { { arg {} } } {
  variable controller
  if { ! [info exists controller] } {
    set controller [ mixin new ]
  }
  return [$controller redelay $arg]
}

proc ::redelay::new { {max {}} } {
  set controller [mixin new]
  if { $max ne {} } {
    $controller redelay_max $max
  }
  return $controller
}
