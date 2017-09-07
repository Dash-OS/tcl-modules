package ifneeded tcl-modules 1.0 [list apply {{dir} {
  # simply add our tcl-modules path to the tm path
  # so they can be required.
  ::tcl::tm::path add $dir
  package provide tcl-modules 1.0
}} $dir]
