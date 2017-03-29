# Tcl State Manager (TSM)

> **Note:** Currently setup to work in the Tcl Package Manager we have not yet released 
> so this likely will not work quite yet without some changes.  This is just an initial
> commit.

Managing the state of our applications can often prove to be a task which gets
more and more unorganized and messy as our applications grow and evolve.  As 
more side effects are built off of our data model(s) it becomes a necessity to 
have a clear way to organize and manage the application state. 

TSM was built to solve this need.  It provides many powerful core features 
that make it extensible, useful, and downright powerful.

#### Core Features

 - Singleton or "Keyed" states supported
 - Extendable type validation
 - Extendable "query builders" and "modifiers"
 - Include or build "middlewares" that hook into the lifecycle
 - Powerful and absolutely simple "getters" and "setters"

#### Included Middlewares

 - Query Subscriptions (execute $cmd when meets conditions)
 - Persistent Layer via sqlite 
 - JSON Serialization via yajltcl
 - Simple API to build & share your own!

## Introduction

TSM is a schema-backed state management utility which uses many optimization 
techniques to provide a performant and reliable state layer to your application(s).

It is not meant to be a general-purpose data container like **`[dict]`** or **`[list]`** but 
rather a tool to manage and maintain your important pieces of state within your 
application.  

## Registering a State Schema

Lets start by looking at a simple example of registering a "singleton" state within 
our application.

```tcl
state register MyState {
  items {
    required string foo
    required number bar
    optional ip     baz
  }
}
```

This provides us with a data model which ends up taking the form: `[dict create foo <string> bar <number> ip <ip>]`.
Each value is validated when set to insure our data matches the expected format.  We have also identified 
`foo` and `bar` as required items which means we will not be able to set our state at all unless they are defined 
in the first "setting" of the state.  In this case that may not be as useful, but more on that later.

The full API of the registration will come.  

## Setting Your State

Setting of the state uses the same `[state]` command that we used for registration.

### Singleton State 

In it's simplest form it takes the same form as setting a `[dict]`.

```tcl
state set MyState [dict create foo foo bar 123]
```

State is meant to be managed throughout your application.  Setting of your state will cause a (merge)
with the previous values (if any).  For example, when we set our state again but only provide the ip, 
it does not raise an error because foo and bar are already included.  

```tcl
state set Mystate [dict create ip 192.168.1.1]
```

Our state will now take a form which resembles `[dict create foo foo bar 123 ip 192.168.1.1]`

### Keyed State


Keyed State provides us with a much more powerful data layer.  With keyed state, each unique 
"key" will be a separate "entry" within your state.  Your data is de-normalized and saved in a 
way which makes it easy to extend and build upon.

Here is an example of a more powerful "keyed" schema which provides us with indexed keys, configuration options, "middlewares", and more.

```tcl
state register MyKeyedState [dict create async 1 batch 0] {
  middlewares { persist subscriptions }
  config { async $async batch $batch }
  items {
    key number      integrationID
    required bool   active
    optional bool   state
    optional string ref
  }
}
```

> Middlewares are also supported with singleton state containers.

With keyed state, the "key" is required every time you wish to set an entry within your state. Lets 
imagine our application is running and setting the state at various points:

```tcl
state set MyKeyedState [dict create integrationID 1 active 0]
state set MyKeyedState [dict create integrationID 2 active 1 state 0]
state set MyKeyedState [dict create integrationID 3 active 0 state 1 ref fooRef]
state set MyKeyedState [dict create integrationID 1 active 1]
state set MyKeyedState [dict create integrationID 1 ref barRef]

# These would produce errors

% state set MyKeyedState [dict create integrationID 4 state 1]
[State MyKeyedState]: <Schema Error> missing required item "active" 
while attempting to set "integrationID 4 state 1"

% state set MyKeyedState [dict create integrationID 4 active foo]
[State MyKeyedState]: <Type Error> while setting "active", expected "bool"
```

Our state will now look something like:

```tcl
{
  1 {active 1 ref barRef}
  2 {active 1 state 0}
  3 {active 0 state 1 ref fooRef}
}
```

#### Setting Multiple Values

We can also set multiple values simultaneously when needed.

```tcl
state set MyKeyedState \
  [dict create integrationID 1 active 0] \
  [dict create integrationID 2 active 1 state 0] \
  [dict create integrationID 3 active 0 state 1 ref fooRef]
```

### Getting Our State

There are quite a few powerful ways that we can query and get our state based upon 
our needs as our application does its thing.  In it's simplest form we simply call
`[state get]` with the name of the state.

#### Singleton State

```tcl
% set state [state get MyState]
foo foo bar 123 ip 192.168.1.1
```

#### Keyed State

```tcl
% set state [state get MyKeyedState]
1 {active 1 ref barRef} 2 {active 1 state 0} 3 {active 0 state 1 ref fooRef}
```

However, we also a few other options that we can use to filter our results. Below
are a few of the options that can be used

```tcl
% set data [state get MyState foo ip]
foo foo ip 192.168.1.1

% set data [state get MyState ip]
ip 192.168.1.1

% set data [state get MyKeyedState [list 1 3]]
1 { active 1 ref barRef } 3 { active 0 state 1 ref fooRef }

% set data [state get MyKeyedState [list 1 3] [list active]
1 {active 1} 3 {active 0}

% state pull MyState foo bar
% puts "$foo $bar"
foo 123

% state pull MyKeyedState 3 active ref
% puts "Key 3 has active $active with ref $ref"
Key 3 has active 1 with ref fooRef

% set data [state get MyKeyedState {} [list ref active]]
1 {active 1 ref barRef} 2 {active 1} 3 {active 0 ref fooRef}

% set values [state withKey MyKeyedState {} state]
1 1 2 1 3 0

% set values [state withKey MyKeyedState {} ref]
1 barRef 3 fooRef

% set keys [state keys MyKeyedState]
1 2 3

% set results [state query MyKeyedState [dict create match foo* ids [list 1 2 3]] {
    ref match        | $match
    integrationID in | $ids
  }]
3

% set values [state values MyKeyedState]
{integrationID 1 active 1 ref barRef} {integrationID 2 active 1 state 0} 
{integrationID 3 active 0 state 1 ref fooRef}

# Assumes serializer middleware is defined
% set json [state serialize MyKeyedState [list 1 2] ref
{ "1": { "ref": "barRef" } } ; # Only 1 has "ref"

```

As I have time I will go into detail on the following.  Below are various examples 
of extending and building the state, using middleware, and/or examples of commands:


### Subscriptions Middleware

Subscriptions used to follow a pattern more like proc where you would define
{arg1 arg2 arg3...}, but it is far more performant to evaluate the script within 
the context of our evaluator, giving you access to many variables. 

It is probably a good idea to use the "body" of the subscription to call your 
commands rather than writing long scripts within the body itself.

The executed body has directly access to the entire context that caused the execution
which is the data structure passed to middlewares.  The "snapshot" is unique to the 
given key within the state and does not reflect information about any other key.

Below is a general example of each variable as well as an idea of the form it will 
have and the data that will be present.

```tcl
$keyID    <key id>
$keyValue <key value>
$set      [list <...keys set>]
$created  [list <...keys created>]
$changed  [list <...keys changed>] 
$keys     [list <...keys present>]
$removed  [list <...keys removed>]
$setters  [dict create <...dict provided during subscribe, if any>]
$items    [dict create 
  <itemKey> [dict create value <current value> prev <previous value>]
  <...other items>
]
```

```tcl
state subscribe MyKeyedState [dict create one two] {
  conditions {
    ip match | 192.168*
  }
} { 
  puts "Subscription Activated for $keyID"
  puts "Key Value: $keyValue"
  puts "Items: $items"
  
  # ... call your command!
}
```

```tcl
state subscribe MyKeyedState [dict create op > n 2] {
  conditions {
    ref changed
    active = | 1
    integrationID $op | $n
    ip match | 192.168*
  }
} { 
  puts "Subscription Activated for $keyID"
  puts "Key Value: $keyValue"
  puts "Items: $items"
  puts "Setters: $setters" ; # {op > n 2}
  # ... call your command!
}
```

> By default subscriptions are both asynchronous and provide "snapshot batching".  This means 
> that we intelligently merge snapshots that occcur within the same event loop evaluation and 
> will not run the evaluation until the event loop calls it.  
>
> You may use "config" to modify this behavior. 

```tcl
state subscribe MyKeyedState [dict create op set] {
  config { async 1 batch 0 }
  conditions { ref changed; active $op }
} { ... }
```

### State Persistent Middleware

When provided during registration, the state will be persisted into a sqlite 
database.  Similar to subscriptions, persistence evaluation is both asynchronous
and batches snapshots unless specified otherwise through the configuration.

Will go more into this in the future, but it's essentially completely transparent. 
It also automatically modifies and copies tables as you change the schema so that,
if possible, we will copy the values over to the new schema.



### Custom Types 

Variables available to type validators are as follows:

```tcl
$value    <current value>
$prev     <previous value>
$params   [list <...params defined after | during registration>]
$setters  [dict create <...dict provided during subscribe, if any>]
```

In addition to validation, types can define hooks that will be processed before 
and after validation occurs.  This allows us to setup a value for evaluation 
and, if needed, modify it before it is saved to our state.

```tcl
state type register enum {
  validate { expr { $value in $params } }
  json {
    if {[string is entier -strict $value]}     { $json map_key $key number $value
    } elseif {[string is bool -strict $value]} { $json map_key $key bool   $value
    } else {                                     $json map_key $key string $value
    }
  }
}

# Modify bools to always be saved as 0 / 1 for unified processing and queries
state type register bool {
	validate { string is bool -strict $value }
	post     { expr { bool($v) } }
	json     { $json map_key $key bool $value }
}

# Normalize IP before we validate.  In this case [ipNormalize] returns an empty 
# string if the value was not a valid IP.  This also insures all IP's saved to our 
# state with this type will be normalized.
state type register ip {
	pre      { ipNormalize $value  }
	validate { expr {$value ne {}} }
	json     { $json map_key $key string $value }
}
```

> `json` is only required for the serializer middleware and is likely to be changed 
> to become part of its configuration / setup.





### Custom "Queries" 

Queries are utilized by the `[state query]` commands to provide a means for filtering
the state and efficiently finding any matching keys.  In addition, the compiled expressions
are made available for use outside of the query command (for example, with `[state subscribe]`)

Queries "evaluate" command is evaluated in the same context as queries and subscriptions so they 
have access to the same variables defined above (`snapshot`).  In addition they have access to 
(and technically so do subscription scripts):

```tcl
$value  <value of queried>
$prev   <prev value of queried>
$params <params provided after | during registration>
```

```tcl
# conditions { name created }
state query register created {
  active 1
  alias {added}
  evaluate { expr { $key in $created || ( $key eq "*" && $created ne [list] ) } }
}

# conditions { name removed }
state query register removed {
  active 1
  alias {deleted}
  evaluate { expr { $key in $removed || ( $key eq "*" && $remove ne [list] ) } }
}

state query register >_ {
  active 1
  alias {"rises above"}
  evaluate { expr { $value > $params && $prev <= $params } }
}

# conditions { name = | foo }
state query register = {
  alias {eq == equal}
  evaluate { expr { $value == $params } }
}

# conditions { name not equal | bar }
state query register != {
  alias {ne "not equal"}
  evaluate { expr { $value != $params } }
}

# conditions { name match | -nocase br* }
state query register match {
  evaluate {
    if {"-nocase" in $params} {
      set params [string trim [string map {"-nocase" ""} $params]]
      lappend args -nocase
    } else { set args {} }
    string match {*}$args $params $value
  }
}

```

> Note that "active" is an important property which indicates that we are expecting 
> that the given value must have been <set> in order to evaluate as true.  Therefore 
> we can optimize evaluations in a significant way when active queries are defined.
>
> In addition, active queries are always evaluated before inactive queries.

### Query Modifiers

We may also define "query modifiers" which provide hooks into a queries lifecycle 
when defined.  These allow us to modify the values before the query evaluates them
so that we can provide a more powerful level of evaluation and customization.

Modifiers may be chained and will be executed in the order they were defined. Currently
we only have "before-eval" and "after-eval" as options.  Both may be defined.  

 - **after-eval**  - $result will be true/false -- has access to same variables as query.
 - **before-eval** - any modifications to variables will be evaluated by the query evaluator.

```tcl
# These allow us to define out subscription modifiers 
# conditions { name changed } - otherwise a single argument would be an error.
state modifier register set {}
state modifier register removed {}
state modifier register is {}

# Change $value to $prev
# conditions { name was != | foo }
state modifier register was {
	before-eval { set value $prev }
}

# conditions { name not match | *foo }
state modifier register not {
	after-eval { set result [ string is false -strict $result ] }
}

# Chained Example
# conditions { name was not match | *foo }

```

### Custom Middlewares

Middlewares are simple to build and allow you to hook into the lifecycle of 
the state which defines requests the given middleware.


#### Middleware Mixins

We start by providing a middleware that can be used by any registered state.  This 
process will define methods that we wish to mixin to the various steps within our 
state.  

You may define some or no mixins depending on its use.

 - **api**       - [state $method $args $body]
 - **container** - Generally api will call the container which can be retrieved by 
                   calling [my ref $localID]
 - **entry**     - An entry for our keyed state (and singleton which only has one)
 - **item**      - Each items container holding an index of current/prev values

```tcl
state middleware provide myMiddleware [namespace current]::MyMiddlewareClass {
  ...middlewareConfig
} {
  api {
    method myMiddleware { localID args } {
    
    }
  }
  container {
    method myMiddleware { subscription } {
    
    }
  }
  entry {
    method ...
  }
  item {
    method ...
  }
}
```

> The middlewareConfig is meant to assist in bringing values from the local context or 
> namespace into the instance when created.  It is not meant to be used to configure 
> by the end-user / while register your scripts.  

#### Middleware Object

When we registered our middleware, we provided a callback to a TclOO class which will 
be built and added to our State when requested.  The class will be built into the 
states namespace and will have access to the various commands and options to assist 
with its needs.

During registration, our state will check to see which lifecycle hooks have been 
defined by the middleware and will call the methods when appropriate.

Below we see a class built using the meta class `class@` which is used to help us
evaluate within both the namespace and context of our state / defintition.

```tcl
class@ create MyMiddlewareClass {

  variable CONTAINER CONFIG
  
  constructor { container stateConfig middlewareConfig } {
    set CONTAINER $container
    set CONFIG    $stateConfig
  }

  destructor {
    
  }
  
  # onSnapshot is called by the middleware processor whenever a new snapshot is 
  # available to parse.
  method onSnapshot { snapshot } {
  
  }
  
  # When a key is created on the state
  method onCreated { snapshot } {
   
  }
  
  # When a key is removed from the state
  method onRemoved { snapshot } {
    
  }
  
  # When an error occurs anywhere during evaluation
  method onError { result options } {
    
  }
	
}
```# tcl-state-manager
