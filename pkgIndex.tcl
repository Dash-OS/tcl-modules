package ifneeded tcl-modules 1.0 [list apply {{dir} {
  # simply add our tcl-modules path to the tm path
  # so they can be required.
  ::tcl::tm::path add \
    [file normalize \
      [file join \
        [file dirname [info script]] tcl-modules
      ]
    ]
}} $dir]
