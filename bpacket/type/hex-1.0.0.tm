if 0 {
  @ bpacket type: hex @
    simple hex encode/decode
}
::oo::class create ::bpacket::type::hex {

  method @encode::hex value {
    if {[string is true -strict $value]} {
      return [binary format c 1]
    } else {
      return [binary format c 0]
    }
  }

  method @decode::hex {} {
    binary scan $BUFFER ca* bool BUFFER
    return $bool
  }

}
