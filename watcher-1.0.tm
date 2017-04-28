package require ensembled
namespace eval watcher { ensembled }

proc ::watcher::awaitfile { path {interval 5000} {callback {}} {timeout {}} {expect 1} } {
  tailcall ::watcher::awaitsubscribe \
    [list file exists $path] $interval $callback $timeout $expect
}

# proc ::watcher::await_touched { path { interval 5000 } { callback {} } {timeout {}} {expect 1} } {
#   if { [file exists $path] } {
#     set mtime [file mtime $path]
#     set atime [file atime $path]
#   } else { tailcall [namespace code [list awaitfile $Path $interval $callback $timeout $expect]] }
# }

proc ::watcher::awaitsubscribe { check {interval 5000} {callback {}} {timeout {}} {expect 1} {result 1} } {
  set async [ expr { $callback ne {} } ]
  if { [{*}$check] eq $expect } {
    if { $async } { after 0 [list {*}$callback $result] }
    return 1
  }
  if { $async && ! [string match ::watcher::proc::await_* [info coroutine] ] } {
    if { ! [namespace exists ::watcher::proc] } { 
      namespace eval ::watcher::proc {} 
    }
    tailcall coroutine \
      ::watcher::proc::await_[clock milliseconds] \
      ::watcher::awaitsubscribe $check $interval $callback $timeout
  }
  if { [string is entier -strict $timeout] && $timeout < 6e9 } {
    set timeout [ expr { [clock milliseconds] + $timeout } ]
  }
  if { $async } { after 0 [list catch [list [info coroutine]]] ; yield [info coroutine] }
  while { [{*}$check] ne $expect } {
    if { [string is entier -strict $timeout] && $timeout <= [clock milliseconds] } { set result 0; break }
    if { $async } {
      after $interval [ list catch [list [info coroutine] continue] ]
      set cmd [yield]
      if { [string equal $cmd cancel] } { set result 0; break }
    } else { after $interval }
  }
  if { $async } { after 0 [list {*}$callback $result] }
  return $result
}

proc ::watcher::watcher { check {expect 1} interval callback {timeout {}} {result continue} } {
  if { ! [ string match ::watcher::proc::watcher_* [info coroutine] ] } {
    if { ! [info exists ::watcher::i] } { set ::watcher::i 0 }
    if { ! [namespace exists ::watcher::proc] } { 
      namespace eval ::watcher::proc {} 
    }
    tailcall coroutine \
      ::watcher::proc::watcher_[incr ::watcher::i] \
      ::watcher::watcher $check $expect $interval $callback $timeout
  }
  after 0 [info coroutine]; yield [info coroutine]
  while 1 {
    if { ! [string equal $result continue] } {
      if { [string is false -strict $result] || [string equal $result cancel] } { break }
      if { [string is true -strict $result] } { catch { {*}$callback $result } }
      after $interval [list [info coroutine] continue]
      set result [yield]
    } else {
      set watcher [::watcher::awaitsubscribe $check $interval [info coroutine] $timeout $expect]
      set result  [yield]
    }
  }
  if { ! [string equal [info commands $watcher] {}] } { 
    catch { $watcher cancel } 
    catch { rename $watcher {} }
  }
  catch { {*}$callback $result }
  if { [info commands ::watcher::proc::*] eq {} } { namespace delete ::watcher::proc }
}

proc ::watcher::killall {} { catch { namespace delete ::watcher::proc } }
