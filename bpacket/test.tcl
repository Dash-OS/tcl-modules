package require bpacket

# below we see various forms of each type
# which expect a different method of providing
# the values to the encoder.

# when flags or numlist has no arguments then
# it is a dynamic list of booleans or numbers whereas
# when arguments are provided, those values must be
# within a dict with the given keys (all are required currently)
set template {
  1 string id
  2 list   values
  3 dict   data | one two three
  4 numlist nums
  5 numlist nums2 | one two three
  6 flags   flags
  7 flags   flags2 | one two three
}

set data [dict create \
  id "some_id_value" \
  values [list one two three] \
  data   [dict create one ONE two TWO three THREE] \
  nums   [list 100 90 80 70 60 50 40 30 20 10 0] \
  nums2  [dict create one 1 two 2 three 3] \
  flags  [list true false false] \
  flags2 [dict create one true two false three false]
]

# used to differentiate chunking when we test the fragmented stream
set data2 [dict create \
  id "another_id" \
  values [list one two three] \
  data   [dict create one ONE two TWO three THREE] \
  nums   [list 100 90 80 70 60 50 40 30 20 10 0] \
  nums2  [dict create one 1 two 2 three 3] \
  flags  [list true false false] \
  flags2 [dict create one true two false three false]
]

if {[info command ::io] ne {}} {
  ::io destroy
}

bpacket create io ::io $::template

set encoded  [io encode $data]
set encoded2 [io encode $data2]

# id some_id_value values {one two three} data {one ONE two TWO three THREE}
# nums {100 90 80 70 60 50 40 30 20 10 0} nums2 {one 1 two 2 three 3}
# flags {1 0 0} flags2 {one 1 two 0 three 0}
# -------------------------------------------
# Data Length:  207
# zlib Deflate: 133
# Encoded:      80
#
# Decoded Data:
# id some_id_value values {one two three} data {one ONE two TWO three THREE} nums {100 90 80 70 60 50 40 30 20 10 0} nums2 {one 1 two 2 three 3} flags {1 0 0} flags2 {one 1 two 0 three 0}
#
# Start Benchmark:
#
# encode: 69.461 microseconds per iteration
# decode: 104.08 microseconds per iteration
# -------------------------------------------
proc benchio {} {
  set ::decoded [io decode $::encoded]
  puts "
-------------------------------------------
Data Length:  [string length $::data]
zlib Deflate: [string length [zlib deflate $::data]]
Encoded:      [string length $::encoded]

Decoded Data:
$::decoded

Start Benchmark:

encode: [time {io encode $::data} 1000]
decode: [time {io decode $::encoded} 1000]
-------------------------------------------
  "
}

benchio

proc validateio {} {
  # use the call/lambda package
  package require call
  # should return an empty string after it parses the field with id 6 (flags)
  set decoded [io decode $::encoded \
    -validate [-> field {
      puts "validating $field"
      switch -- [dict get $field id] {
        6 {
          puts "id 6 found - cancel packet parsing"
          return false
        }
      }
    }]
  ]

  if {$decoded eq {}} {
    puts "decode cancellation success"
  }
}

# the header start values wont print - they are there to see the logic
# process here.
#  -- SIMPLE STREAM TEST --
#
# bpacket header start: 0
# Received Complete Packet for chan: SIMPLE
# Decoded: id some_id_value values {one two three} data {one ONE two TWO three THREE} nums {100 90 80 70 60 50 40 30 20 10 0} nums2 {one 1 two 2 three 3} flags {1 0 0} flags2 {one 1 two 0 three 0}
#
#  -- SIMPLE STREAM TEST COMPLETED! --
#
#
#  -- CHUNKED STREAM TEST --
#
# bpacket header start: 0
# bpacket header start: 0
# Received Complete Packet for chan: CHUNKED
# Decoded: id some_id_value values {one two three} data {one ONE two TWO three THREE} nums {100 90 80 70 60 50 40 30 20 10 0} nums2 {one 1 two 2 three 3} flags {1 0 0} flags2 {one 1 two 0 three 0}
#
#  -- FRAGMENTED STREAM TEST --
#
# bpacket header start: 0
# bpacket header start: 64
# bpacket header start: -1
# Received Complete Packet for chan: CHUNKED2
# Decoded: id some_id_value values {one two three} data {one ONE two TWO three THREE} nums {100 90 80 70 60 50 40 30 20 10 0} nums2 {one 1 two 2 three 3} flags {1 0 0} flags2 {one 1 two 0 three 0}
# Received Complete Packet for chan: CHUNKED2
# Decoded: id another_id values {one two three} data {one ONE two TWO three THREE} nums {100 90 80 70 60 50 40 30 20 10 0} nums2 {one 1 two 2 three 3} flags {1 0 0} flags2 {one 1 two 0 three 0}
proc teststream {} {
  if {[info command ::stream] ne {}} {
    puts "Destroy Stream"
    ::stream destroy
  }

  bpacket create stream ::stream

  stream event onPacket

  simplestream

  chunkedstream

  fragmentedstream
}

proc simplestream {} {
  # start append tests
  # final argument is optional and can be used to
  # separately handle multiple streams / chans at once.
  puts "\n -- SIMPLE STREAM TEST -- \n"
  # append a simple and complete packet
  stream append $::encoded SIMPLE

  # flush our eventstream
  update

  puts "\n -- SIMPLE STREAM TEST COMPLETED! -- \n"
}

proc chunkedstream {} {
  puts "\n -- CHUNKED STREAM TEST -- \n"
  # append the encoded message in two chunks
  stream append [string range $::encoded 0 15] CHUNKED
  update
  stream append [string range $::encoded 16 end] CHUNKED
  update
}

proc fragmentedstream {} {
  puts "\n -- FRAGMENTED STREAM TEST -- \n"
  # append chunks of packet out of order -- we expect that a total of
  # two packets will be assembled from this process

  # this will end up being trashed when it cant build the complete packet
  # stream append [string range $::encoded 0 15] CHUNKED2
  # # then we will move to this one
  stream append [string range $::encoded 0 10] CHUNKED2
  # # receiving some more of the previous packet
  stream append [string range $::encoded 11 20] CHUNKED2
  # # completing the first packet
  stream append [string range $::encoded 21 end] CHUNKED2
  update

  # # finally the first packets tail comes in - but cant really be used
  stream append [string range $::encoded 16 end] CHUNKED2
  # # a new packet starts
  stream append [string range $::encoded2 0 20] CHUNKED2
  # # and completes
  stream append [string range $::encoded2 21 end] CHUNKED2
  # # then some random junk
  stream append [string range $::encoded 21 30] CHUNKED2

  update
}

proc onPacket {packet chanID} {
  puts "Received Complete Packet for chan: $chanID"
  set decoded [io decode $packet]
  puts "Decoded: $decoded"
}
