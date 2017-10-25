# this can be ignored - saving it here in case need to reference it
# -- includes some optimizations that have since been removed
# variable eval_noargs {
#   set oargs [lrange $args 0 end-[llength $argnames]]
#   set args  [lrange $args end-[expr {[llength $argnames] - 1}] end]
#   try $::optcmds::eval_simple
# }
#
# variable eval_withargs {
#   if {[set dashdash [lsearch -exact $args --]] != -1} {
#     set oargs [lrange $args 0 ${dashdash}-1]
#     set args  [lrange $args ${dashdash}+1 end]
#     try $::optcmds::eval_simple
#   } else {
#     try $::optcmds::eval_withargs_nodash
#   }
# }

# variable eval_simple {
#   set opts [dict create]
#   while {[llength $oargs]} {
#     set oargs [lassign $oargs opt]
#     if {![dict exists $odef $opt]} {
#       try $::optcmds::error_illegal_opt
#     } elseif {[dict get $odef $opt] eq {}} {
#       # dict set opts [string trimleft $opt -] 1
#       dict set opts $opt 1
#     } elseif {![llength $oargs]} {
#       try $::optcmds::error_expects_val
#     } else {
#       set oargs [lassign $oargs val]
#
#       if {[string index $val 0] eq "-" && [dict exists $odef $val]} {
#         try $::optcmds::error_expects_val
#       }
#       # dict set opts [string trimleft $opt -] $val
#       dict set opts $opt $val
#     }
#   }
# }



# main downside here is that we really do not have a way of
# reliably determining if we have received an invalid opt or
# if it is meant to be apart of the regular arguments.  thus, the
# -- is highly recommended when using $args for better error messages
# and more reliable handling.
# variable eval_withargs_nodash {
#   set opts [dict create]
#   while {[dict exists $odef [lindex $args 0]]} {
#     set args [lassign $args opt]
#     if {[dict get $odef $opt] eq {}} {
#       # dict set opts [string trimleft $opt -] 1
#       dict set opts $opt 1
#     } elseif {![llength $args]} {
#       try $::optcmds::error_expects_val
#     } else {
#       set args [lassign $args val]
#       # TODO: should this throw an error?  its possible this arg wants the
#       #       name of another arg as its parameter - however probably best
#       #       to use the name without the - switch in that case.  open to
#       #       ideas here.
#       if {[string index $val 0] eq "-" && [dict exists $odef $val]} {
#         try $::optcmds::error_expects_val
#       }
#       # dict set opts [string trimleft $opt -] $val
#       dict set opts $opt $val
#     }
#   }
# }

# if {[lindex $argnames end] ne "args"} {
#   # optimized version when args arent given
#   lappend process $::optcmds::eval_noargs
# } else {
#   # handle when dynamic args are at the end.  here we cant easily separate the
#   # options since we cant know how many arguments and/or options that we
#   # may have. If -- is provided when invoked, we will still be able to optimize,
#   # otherwise we need to parse one-by-one until we find what "appears" to be a non-matching
#   # option key.
#   lappend process $::optcmds::eval_withargs
# }

# handle when dynamic args are at the end.  here we cant easily separate the
# options since we cant know how many arguments and/or options that we
# may have. If -- is provided when invoked, we will still be able to optimize,
# otherwise we need to parse one-by-one until we find what "appears" to be a non-matching
# option key.
# lappend process $::optcmds::eval_withargs
#
#
#
# ****OPINION: Option Parsing is Hard (annoying?)****
#
# If you look around at user-provided packages you will find a variety of ways are given for interacting with them.  While most built-in commands take the form of''' `[cmd ?options? ...args]`''', it is rare to see it provided elsewhere.  This is likely due to the fact that it can be fairly difficult, slow, and error-prone to parse options in this way.  It has become much more common to simply put those switches into '''`$args`''' which in some cases is a great solution and makes the most sense.
#
# This is where this proposal comes in.  We are specifically targeting the parsing and handling of options, which share many traits with named arguments.  Personally I see `options` and `arguments` as different things.  Options are "modifiers" that server as instructions to our command as-to''''' how it should act'''''.  Arguments, on the hand, '''''serve as the input to our command'''' which are then acted upon based on the given options.  Therefore, while named arguments generally end up merging both concepts into one, keeping them separated as two concepts can make code easier to understand and work with.
#
# If you browse through any of the open source packages, you will find different mechanisms being built for parsing of options - it's time to unify this so that Tcl programs begin to take on a more unified approach to passing options & arguments.  While you could absolutely argue the (most) common Tcl way for handling options is not the best option, it is how they are (and will continue to be) for the long-run.
#
# ****OPINION: Named Argument Definition can be ugly****
#
# In general, while the original author actually supports both named argument TIP's, they do seem to have certain drawbacks.  One could also argue that they try to do too much, creating what ends up being it's own mini DSL that starts to handle logic rather than simply defining what arguments the given command expects.  Shortcuts are great, but adding new syntax rules and concepts can start to make the language feel all over the place.  Why not KISS?
#
# There are some very good reasons behind the many features the named arguments syntax provides.  While I can admit there have been many times I have wanted each of these features (upvar, aliasing, switches, etc), it can end up detaching too much logic from the script itself, making it hard to read and understand without spending time "connecting the dots."
#
# Below is an example of the definition for named arguments.  If you are not familiar with the specification & syntax itself, this will likely serve as a great example.  Can you tell exactly what this command is expecting and how to call it?  Sure, documentation will help - but should it be required to find some external documentation when working with your source?  This is even a simple example with a single argument.  It can also get much more complex with more arguments as they are needed.
#
# ======
# proc p { { level -name lvl -switch {{quiet 0} {verbose 9}} } {
#      list level $level
# }
# ======
#
# What about when we need more than one argument?!  While it is the authors personal opinion here, it just becomes hard to understand the intent of the argument definition without either being the author of the code and/or spending time with the documentation to grasp what is going on.  Sure, its awesome to save a few lines of code in the body of the proc and use our little "arg scripting language" to do some logic, but it just seems like its trying to do too much.
#
# ======
# proc p { { level -name lvl -switch {{quiet 0} {verbose 9}} { inc -name i -upvar 1 -required 1 } { v -name var } a } {
#      list level $level
# }
# ======

# Many of these options are made to "transform" the names of the arguments from how they are given to the command to how they are evaluated by the command.  Or to provide multiple ways of setting a single argument (shortcuts).  Most of these shortcuts end up being things that could be done in the body of the command with a single expression or if/else statement.  It is not the authors intent to "bash" this syntax, only to question if it makes sense to aim for something simpler and focuses on the biggest drawback of handling options & arguments that are non-positional: performance - rather than trying to make them handle the logic for us.
#

proc newglob args {
  set arglen [llength $args]
  set index -1
  while {$index < $arglen} {
    set arg [lindex $args [incr index]]
    switch -exact $arg {
      -directory - -path - -types {
        set opts($arg) [lindex $args [incr index]]
      }
      -nocomplain - -tails - -join {
        set opts($arg) 1
      }
      -- {
        break
      }
      default {
        # validation is going to be required here -- did they provide an invalid
        # switch or is it simply that we have gotten to the actual arguments and
        # the optional -- was not provided?  this can be a source of errors and
        # more verbose code required.
        break
      }
    }
  }

  set args [lrange $args $index end]

  # now we can handle our opts and see what we need to do next
  # -- we may need to validate and/or confirm values exist and/or
  # that they are the what we expect.

  if {[info exists opts(-directory)]} {
    puts "-directory switch set"
    # ... code what happens for -l
  }
}


proc newglob {
  -directory directory
  -path  filepath
  -types filetypes
  -nocomplain
  -tails
  -join
  -- args
} {

}


while {[llength [lassign $fl b]]} {append data [binary format c $b]}

while {[string length [binary scan $data ca* b data]]} {lappend fl $b}
