# pretty much identical to tcllib [lambda] with a diff name
# returns a command which builds a lambda expr - optionally with
# some values pre-populated
proc -> {pargs script args} {
  list ::apply [list $pargs $script] {*}$args
}

# immediately invoked lambda
# probably only useful in some cases where
# we want to execute some code without polluting the
# current scope.
# +> foo { set bar $foo ; puts $bar } foo!
proc +> {pargs script args} {
  tailcall ::apply [list $pargs $script] {*}$args
}

# call without needing to expand
# call [-> foo { puts $foo }] foo!
proc call {lam args} { tailcall {*}$lam {*}$args }
