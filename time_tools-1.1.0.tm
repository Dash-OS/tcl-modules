package require task
package require tasks::every

namespace eval ::Time {
  variable ClockID         {}
  variable GetTimezoneURL  http://ip-api.com/json
  namespace ensemble create
  namespace export *
}

# This is an old package - lots of cleanup required and not meant for public use

proc ::Time::Timezone {} {
  if {[state exists GlobalData]} {
    state pull GlobalData timezone
    if { $timezone eq {} } {
      set data [::Time::GetTimezone]
      if { [dict exists $data timezone] } {
        return [dict get $data timezone]
      } else {
        return
      }
    } else {
      return $timezone
    }
  } else {
    set data [::Time::GetTimezone]
    if { [dict exists $data timezone] } {
      return [dict get $data timezone]
    }
  }
  return
}

proc ::Time::GetTimezone {} {
  try {
    set token [::http::geturl $::Time::GetTimezoneURL -timeout 10000]
    set data  [::http::data $token]
    ::http::cleanup $token
    if { $data ne {} } {
      set data     [json get $data]
      set response [dict create]
      if { [dict exists $data timezone] } {
        set timezone [dict get $data timezone]
        set timezone :[string trimleft $timezone :]
        dict set response timezone $timezone
      }
      if { [dict exists $data isp] } {
        dict set response isp [dict get $data isp]
      }
      if { [dict exists $data query] } {
        dict set response query [dict get $data query]
      }
      if { [dict exists $data zip] } {
        dict set response zip [dict get $data zip]
      }
      if { [dict exists $data regionName] } {
        dict set response regionName [dict get $data regionName]
      }
      if { [dict exists $data city] } {
        dict set response city [dict get $data city]
      }
      if { [dict exists $data countryCode] } {
        dict set response country [dict get $data countryCode]
      }
      if { [info commands ::state] ne {} && [state exists GlobalData] } {
        state set GlobalData [dict pickIf $response isp timezone zip city country]
      }
      return $response
    }
  } on error {result options} {
    ::onError $result $options "While Capturing the Timezone Data"
    if { [info exists token] } {
      catch { ::http::cleanup $token }
    }
  }
}


proc ::Time::ParseRange args {
  if { [llength $args] == 1 } { set args [lindex $args 0] }
  if { [string first "and" $args] != -1 } {
    set args [WSplit $args "and"]
  } elseif { [string first "-" $args] != -1 } {
    set args [split $args "-"]
  } elseif { [string first "," $args] != -1 } {
    set args [split $args ,]
  } elseif { [string match -nocase *PM* $args] || [string match -nocase *AM* $args] } {
    set args [string toupper $args]
    set am [string first AM $args]
    set pm [string first PM $args]
    set both [expr { $am != 1 && $pm != -1 }]
    if { $both && $am < $pm } {
      set args [WSplit $args AM]
      if { [llength $args] != 2 } { return }
      lassign $args start end
      append start "AM"
      set args [list $start $end]
    } elseif { $both && $pm < $am } {
      set args [WSplit $args PM]
      if { [llength $args] != 2 } { return }
      lassign $args start end
      append start "PM"
      set args [list $start $end]
    } else {
      set type {}
      if { $am != -1 } {
        set type "AM"
        set args [WSplit $args AM]
      } elseif { $pm != -1 } {
        set type "PM"
        set args [WSplit $args PM]
      } else { return }
      lassign $args start end
      append start $type
      append end $type
      set args [list $start $end]
    }
  }
  if { [llength $args] != 2 } { return }
  set args [trimList $args]
  return $args
}

proc ::Time::Scan {t {opts ""} } {
  set timezone [::Time::Timezone]
  if {$timezone eq {}} {
    return \
      -code error \
      " ::Time::Scan failed to discover timezone"
  }
  set response {}
  set cmd [list clock scan $t -timezone $timezone]
  set next 0
  switch -nocase -- $opts {
    {}      {}
    24      { lappend cmd -format "%R" }
    next    { set next 1 }
    default { lappend cmd -format $opts }
  }
  try {
    set response [ try $cmd ]
    if {$next} {
      set now [clock seconds]
      if {$now >= $response} {
        set response [clock add $response 1 day -timezone $timezone]
      }
    }
  } on error {result options} {
    ::onError $result $options "While Scanning Time: $cmd"
  }
  return $response
}

proc ::Time::R { t {as seconds} {timezone {}} } {
  if {$timezone eq ""} { set timezone [Timezone] }
  switch -glob -nocase -- $as {
    s* {
      # Do Nothing
    }
    m* { set t [expr {$t / 1000}] }
  }
  return [clock format $t -format %R -timezone $timezone]
}

proc ::Time::FormatQuery {timeQueried {timezone ""}} {
  if {$timezone eq ""} { set timezone [Timezone] }
  set parse 1
  set queryLength [string length $timeQueried]
  if { [string is entier -strict $timeQueried] } {
    if {$queryLength >= 13} {
      set timeQueried [expr {$timeQueried / 1000}]
      set timeQueried [expr {round($timeQueried)}]
      set parse 0
    } elseif {$queryLength > 4} {
      set timeQueried [clock format $timeQueried -timezone $timezone -format %R]
      set parse 0
    } else {
      set parse 1
    }
  }
  if {$parse} {
    set timeQueried [Time Scan $timeQueried]
    if {[string first ":" $timeQueried] == -1} {
      if {$queryLength == 4} {
        set splitTime [lassign [split $timeQueried {}] 1 2 3 4]
        set timeQueried {}
        append timeQueried $1 $2 : $3 $4
      } elseif {$queryLength == 3} {
        set splitTime [lassign [split $timeQueried {}] 1 2 3]
        set timeQueried {}
        append timeQueried 0 $1 : $2 $3
      }
    } elseif {$queryLength == 4} {
      set timeQueried 0${timeQueried}
    }
  }
  return $timeQueried
}

proc ::Time::Until {timeQueried { as "ms" } } {
  set secondsNow [clock seconds]
  dict pull [Now] timezone {R timeNow}
  set timeQueried [::Time::FormatQuery $timeQueried $timezone]

  set fNow     [scan [string map {":" ""} $timeNow] %d]
  set fQueried [scan [string map {":" ""} $timeQueried] %d]

  if { $fNow > $fQueried } {
    set baseTime [clock add $secondsNow 1 day -timezone $timezone]
  } else {
    set baseTime $secondsNow
  }

  set timeThen [clock scan $timeQueried \
    -base     $baseTime \
    -timezone $timezone \
    -format   "%R"
  ]

  set durationSeconds [ expr { $timeThen - $secondsNow } ]
  return [::Time::Duration $durationSeconds $as]
}

proc ::Time::Since {timeQueried { as "ms" } } {
  set now      [::Time::Now]
  set timezone [dict get $now timezone]
  set timeNow  [dict get $now R]

  set timeQueried [::Time::FormatQuery $timeQueried $timezone]
  set secondsNow  [clock seconds]

  set fNow     [scan [string map {":" ""} $timeNow] %d]
  set fQueried [scan [string map {":" ""} $timeQueried] %d]

  if { $fNow < $fQueried } {
    set baseTime [clock add $secondsNow -1 day -timezone $timezone]
  } else {
    set baseTime $secondsNow
  }

  set timeThen [clock scan $timeQueried \
    -base     $baseTime \
    -timezone $timezone \
    -format   "%R"
  ]

  set durationSeconds [ expr {$secondsNow - $timeThen} ]
  return [Duration $durationSeconds $as]
}

proc ::Time::Parse args {
  if {[llength $args] == 1} {
    if { [string is entier -strict $args] } { return $args }
    set args [lindex $args 0]
  }
  return [expr { [clock add 0 {*}$args] * 1000 }]
}

proc ::Time::Duration {durationSeconds as} {
  ## Get a duration in seconds and convert it to:
  # milliseconds/ms
  # seconds
  # minutes
  # hours
  switch -glob -nocase -- $as {
    mil* - ms { set duration [expr { $durationSeconds * 1000 } ] }
    se*       { set duration $durationSeconds }
    min*      { set duration [expr { $durationSeconds / 60 }] }
    h*        { set duration [format "%.2f" [expr { double($durationSeconds) / 60 / 60 }]] }
  }
}

proc ::Time::Now {{ timezone {} } { i {} }} {
  set tempDict [dict create]
  if { $timezone eq {} } {
    set timezone [::Time::Timezone]
  }
  try {
    # 18 arguments
    set milliseconds [clock milliseconds]
    set seconds      [clock seconds]
    set timestamp    [clock format $seconds \
      -format "%a %b %d %H:%M:%S %I:%M %p %Z %H%M %m %u %I%M %I:%M %e %W %j %R %y %Y" \
      -timezone $timezone
    ]
    set tempDict [dict create \
  	  24HourFormatted [lindex $timestamp 3] \
  	  12HourFormatted [lindex $timestamp 4] \
  	  DayOfWeekAbbrv  [lindex $timestamp 0] \
  	  MonthAbbrv      [lindex $timestamp 1] \
  	  AMPM            [lindex $timestamp 5] \
  	  YearAbbrv       [lindex $timestamp 16] \
  	  CurrentYear     [scan [lindex $timestamp 17] %d] \
  	  CurrentMonth    [scan [lindex $timestamp 8] %d] \
  	  WeekOfYear      [scan [lindex $timestamp 13] %d] \
  	  DayOfMonth      [scan [lindex $timestamp 2] %d] \
  	  DayOfYear       [scan [lindex $timestamp 14] %d] \
  	  12              [scan [lindex $timestamp 10] %d] \
  	  24              [scan [lindex $timestamp 7] %d] \
  	  DayOfWeek       [scan [lindex $timestamp 9] %d] \
  	  R               [lindex $timestamp 15] \
  	  timezone        $timezone \
  	  milliseconds    $milliseconds \
  	  seconds         $seconds
    ]
  } on error {result options} {
    ::onError $result $options "While Formatting the Current Time"
  } finally { return $tempDict }
}

proc timestamp { {timestamp {}} } {

  if { $timestamp eq {} } {
    set timestamp [clock seconds]
  } elseif { [string length $timestamp] >= [clock milliseconds] } {
    # If we receive milliseconds, we want to change it to seconds
    set timestamp [expr { round( $timestamp / 1000 ) }]
  }

  return [clock format $timestamp \
    -format   "%m/%d/%y at %I:%M %p" \
    -timezone [::Time::Timezone]
  ]

}

proc ZipCode { {retry 0} } {
  state pull GlobalData zip
  if { $zip ne {} } { return $zip }
  if { [string is true -strict $retry] } {
    ::Time::GetTimezone
    return [ZipCode 0]
  }
}

proc City { {retry 0} } {
  state pull GlobalData city
  if { $city ne {} } { return $city }
  if { [string is true -strict $retry] } {
    ::Time::GetTimezone
    return [City 0]
  }
}

proc CountryCode { {retry 0} } {
  state pull GlobalData country
  if { $city ne {} } { return $city }
  if { [string is true -strict $retry] } {
    ::Time::GetTimezone
    return [City 0]
  }
}

proc Timezone {} { tailcall ::Time::Timezone }

proc ::Time::RegisterState {} {
  state register CurrentTime {
    middlewares { subscriptions }
    items {
      required string 24HourFormatted
      required string 12HourFormatted
      required string R
      required string DayOfWeekAbbrv
      required string MonthAbbrv
      required string AMPM
      required number YearAbbrv
      required number CurrentYear
      required number CurrentMonth
      required number WeekOfYear
      required number DayOfMonth
      required number DayOfYear
      required number DayOfWeek
      required number 12
      required number 24
      required string timezone
      required number milliseconds
      required number seconds
    }
  }
  rename ::Time::RegisterState {}
}

proc ::Time::StartClock {} {
  variable ClockID
  if { [info commands ::Time::RegisterState] ne {} } {
    ::Time::RegisterState
  }
  if { $ClockID ne {} } {
    ::every cancel $ClockID
  }
  set ClockID [::every 60000 ::Time::Tick]
  ::Time::Tick
}

proc ::Time::StopClock {} {
  variable ClockID
  if { $ClockID ne {} } {
    ::every cancel $ClockID
    set ClockID {}
    return 1
  } else { return 0 }
}

proc ::Time::Tick {} {
  state set CurrentTime [::Time::Now]
}
