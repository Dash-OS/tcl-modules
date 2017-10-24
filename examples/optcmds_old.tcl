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
