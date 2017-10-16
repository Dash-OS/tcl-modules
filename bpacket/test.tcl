package require bpacket

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

if {[info command ::io] ne {}} {
  ::io destroy
}

bpacket create io ::io $::template

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
# encode: 72.915 microseconds per iteration
# decode: 170.982 microseconds per iteration
# -------------------------------------------
proc benchio {} {
  set ::encoded [io encode $::data]
  set ::decoded [io decode $::encoded]

  puts "-------------------------------------------
Data Length:  [string length $::data]
zlib Deflate: [string length [zlib deflate $::data]]
Encoded:      [string length $::encoded]

Decoded Data:
$::decoded
  "
  puts "Start Benchmark:"
  puts "encode: [time {io encode $::data} 1000]"
  puts "decode: [time {io decode $::encoded} 1000]"
  puts "-------------------------------------------"
}

benchio

proc validateio {} {
  package require call
  set decoded [io decode $::encoded \
    -validate [-> field {
      switch -- [dict get $field id] {
        6 {
          break
        }
      }
    }]
  ]
  puts "Decoded: $decoded"
}
