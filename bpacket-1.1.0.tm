namespace eval ::bpacket {
  namespace ensemble create
  namespace export {[a-z]*}

  # the value used to indiciate the start of the header
  variable HEADER "\xC0\x8D"
  # end of packet - should not be the same as HEADER as we
  # will remove any number of $EOF THEN look for HEADER to
  # determine if we have multiple packets concatted
  variable EOF "\x00\x00"

}

namespace eval ::bpacket::decode {
  namespace ensemble create
  namespace export {[a-z]*}
}

::oo::class create ::bpacket::stream {}
::oo::class create ::bpacket::reader {}
::oo::class create ::bpacket::writer {}

source -encoding utf-8 [file join [file dirname [file normalize [info script]]] bpacket encode.tcl]
source -encoding utf-8 [file join [file dirname [file normalize [info script]]] bpacket decode.tcl]
source -encoding utf-8 [file join [file dirname [file normalize [info script]]] bpacket bpstream.tcl]
