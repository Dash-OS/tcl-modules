
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

puts [string length $data]

bpacket create io ::io $template

set encoded [io encode $data]

puts [string length $encoded]

set decoded [io decode $data]

puts [string length $decoded]

puts $data
