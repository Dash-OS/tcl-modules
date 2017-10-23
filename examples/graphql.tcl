package require json_tools
package require graphql

set QUERY {query (
  $resolve: String!
) {
  onCluster(
    resolve: $resolve
  ) {
    AppStatus {
      status
      isAuthenticated
    }
  }
}}

proc handleGraphRequest request {
  set data   [json get $request]
  set parsed [::graphql::parse $data]
  puts $parsed
  if {[dict exists $parsed requests]} {
    foreach {request params} [dict get $parsed requests] {
      puts "Request: $request"
      puts $params

    }
  }
}

set PACKET [json typed [dict create \
  query [dict create \
    query $QUERY
  ] \
  variables [dict create \
    resolve ""
  ]
]]

puts "GraphQL JSON Request:"
puts [json pretty $PACKET]

puts "---------------------"

handleGraphRequest $PACKET
