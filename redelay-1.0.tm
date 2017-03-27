
::oo::class create redelay_mixin {
  constructor args {
    my variable __redelay_count
    set __redelay_count 0
    catch { next {*}$args }
    return
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
  method __redelay_tick { {max 30} } {
    my variable __redelay_count
    set interval [expr { min( $max,(pow(2,[incr __redelay_count])-1)) * 1000 }]
    set delay    [expr { int( rand() * ( $interval - 1 + 1 ) + 1 ) + 1000 }]
    return $delay
  }
}

proc redelay { { arg {} } } {
  variable controller
  if { ! [info exists controller] } {
    set controller [ [namespace current]::redelay new ]
  }
  return [$controller redelay $arg]
}