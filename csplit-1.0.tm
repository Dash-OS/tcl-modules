# Taken from the cmdSplit / commands wiki page
# http://wiki.tcl.tk/21701
namespace eval ::csplit {}

proc ::csplit::commands args {
  set script [lindex $args end]
  if { [llength $args] > 1 } {
    set flags [lrange $args 0 end-1]
  } else { set flags [list] }
  set commands {}
  set chunk {} 
  foreach line [split $script \n] {
    append chunk $line
    if {[info complete $chunk\n]} {
      # $chunk ends in a complete Tcl command, and none of the
      # newlines within it end a complete Tcl command.  If there
      # are multiple Tcl commands in $chunk, they must be
      # separated by semi-colons.
      set cmd {}
      foreach part [split $chunk \;] {
        append cmd $part
        if {[info complete $cmd\n]} {
          set cmd [string trimleft $cmd[set cmd {}]]
          if {[string match #* $cmd]} {
            #the semi-colon was part of a comment.  Add it back
            append cmd \;
            continue
          }
          set cmd [string trimright $cmd[set cmd {}]]
          #drop empty commands
          if {$cmd eq {}} {
            continue
          }
          lappend commands $cmd
          set cmd {}
        } else {
          # No complete command yet.
          # Replace semicolon and continue
          append cmd \;
        }
      }
      # Handle comments, removing synthetic semicolon at the end
      if {$cmd ne {}} {
          lappend commands [string replace $cmd[set cmd {}] end end]
      }
      set chunk {} 
    } else {
      # No end of command yet.  Put the newline back and continue
      append chunk \n
    }
  }
  if {![string match {} [string trimright $chunk]]} {
      return -code error "Can't parse script into a\
              sequence of commands.\n\tIncomplete\
              command:\n-----\n$chunk\n-----"
  }
  if { "-nocomments" in $flags } {
    return [nocomments $commands]
  }
  return $commands
}

proc ::csplit::nocomments commands {
  set res [list]
  foreach command $commands {
    if {![string match \#* $command]} {
      lappend res $command
    }
  }
  return $res
}
