package ifneeded tcl-modules 1.0 [list apply {{dir} {
  # simply add our tcl-modules path to the tm path
  # so they can be required.
  puts [info script]
  puts "dir $dir"
  ::tcl::tm::path add $dir
}} $dir]
