package require ensembled
namespace eval watcher { ensembled }

proc awaitfile { path {interval 5000} {callback {}} {timeout {}} {expect 1} } {
  tailcall ::utils::awaitsubscribe [list file exists $path] $interval $callback $timeout $expect
}

proc await_touch { path { interval 5000 } { callback {} } {timeout {}} {expect 1} } {
  if { [file exists $path] } {
    set mtime [file mtime $path]
    set atime [file atime $path]
    tailcall 
  } else { tailcall [namespace code [list awaitfile $Path $interval $callback $timeout $expect]] }
}

proc awaitsubscribe { check {interval 5000} {callback {}} {timeout {}} {expect 1} {result 1} } {
  set async [ expr { $callback ne {} } ]
  if { [{*}$check] eq $expect } {
    if { $async } { after 0 [list {*}$callback $result] }
    return 1
  }
  if { $async && ! [string match [namespace current]*proc::await_* [info coroutine] ] } {
    if { ! [namespace exists proc] } { namespace eval proc {} }
    tailcall coroutine [namespace current]::proc::await_[clock milliseconds] {*}[callback awaitsubscribe $check $interval $callback $timeout]
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

proc watcher { check {expect 1} interval callback {timeout {}} {result continue} } {
  if { ! [ string match [namespace current]*proc::watcher_* [info coroutine] ] } {
    if { ! [info exists [namespace current]::i] } { set [namespace current]::i 0 }
    if { ! [namespace exists proc] } { namespace eval proc {} }
    tailcall coroutine [namespace current]::proc::watcher_[incr [namespace current]::i] {*}[callback watcher $check $expect $interval $callback $timeout]
  }
  after 0 [info coroutine]; yield [info coroutine]
  while 1 {
    if { ! [string equal $result continue] } {
      if { [string is false -strict $result] || [string equal $result cancel] } { break }
      if { [string is true -strict $result] } { catch { {*}$callback $result } }
      after $interval [list [info coroutine] continue]
      set result [yield]
    } else {
      set watcher [awaitsubscribe $check $interval [info coroutine] $timeout $expect]
      set result  [yield]
    }
  }
  if { ! [string equal [info commands $watcher] {}] } { 
    catch { $watcher cancel } 
    catch { rename $watcher {} }
  }
  catch { {*}$callback $result }
  if { [info commands [namespace current]::proc::*] eq {} } { namespace delete proc }
}

proc killall {} { catch { namespace delete proc } }

export default watcher
export awaitfile awaitsubscribe await_touch