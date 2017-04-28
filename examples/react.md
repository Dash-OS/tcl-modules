# Tcl React

This is not a true replacement for the excellent Facebook developed library, but it 
mimics it's core concepts and presents our data with the same lifecycle hooks and 
concepts.

Just some examples will be found below.

In general things should look very similar to what you may be used to.  

Below we see the simplest example.  When we require `[react]` it gives us the 
`react` and `Component` commands.  
 
`Component` is a special metaclass which manages the rendering tree for us.  It 
also provides us with our lifecycle method capabilities.

```tcl
package require react

Component create App {
  method render {} {
    puts "Rendered App!"
  }
}

react render App
```

Ok so that isn't very exciting, but it shows the simplest form of a Tcl React Component.
Next lets take a look at adding the concepts provided by [react-redux](https://github.com/reactjs/react-redux) 
to allow updating our UI's state as well as managing it.

Next lets take a look at a little bit more complex example where we might have 
multiple pages to render with components.  Lets break it down in pieces:

Require the packages as well as [callback] (shortcut for [namespace code [list ...]])

```tcl
package require callback
package require react
package require react::reducer
```

In this next example we will take advantage of the redux concept to provide us 
with a top-level store.  Whenever the store **changes** it will render through 
the app.  Only components that might care about the changed value will be 
re-rendered. 

Reducers receive dispatch events and may optionally
set their state.  They do this by returning a >new< state
that should be used.  A re-render will only occur if the result
of running all your registered reducers results in store which is 
not equal to it's previous value.

Lets create a store and provide a reducer that will allow us to reducer the 
"router" key.  We can also define a default state to be used. 
This will essentially create 

```tcl
set store [dict create \
  router [dict create \
    scene home
  ]
]
```



Note that we are only operating on the "router" key with this reducer.  
We may have other reducers operating on different keys.

> **Important:** This should be the ONLY way that data travels into our components.  We 
> should NEVER use global variables or any other method as it may break the rendering lifecycles.

```tcl
# Reducers are how we manage our state.  We create a reducer easily:
react default_store router [dict create \
  scene home
]

react reduce router { store event data } {
  switch -- $event {
    SET_SCENE {
      # When SET_SCENE is dispatched, set the scene to the given value.
      puts "Setting Scene to: $data"
      dict set store scene $data
    }
    default { 
      # We don't care about this event, return the current store unchanged.
    }
  }
  return $store 
}
```

Now lets render our App!  

```tcl
Component create App {

  method RenderReducer {} {
    # We indicate a component is being rendered by prefixing 
    # the components path with *.
    *::react::reducer key reducer \
      onUpdate [callback my forceUpdate]
  }
  
  method render {} {
    puts "App Renders!"
    # This is called on every render, but since we do not update the 
    # properties that we send to it, it will only be rendered once.
    my RenderReducer
    
    # Next we want to capture our store when our app updates so that 
    # we can use it to render our components.
    set store [react store]
    
    puts "Store | $store"
    
    # Now we can use our store to render our UI
    if { [dict exists $store router scene] } {
      # Our router key in our state will help us to route to the 
      # appropriate scene.  Only the components in the given 
      # scene will exist.  The rest will be unmounted when a 
      # scene is changed (because they no longer appear in the render result).
      switch -- [dict get $store router scene] {
        home  { *Home  key home  {*}[dict get $store router] }
        login { *Login key login {*}[dict get $store router] }
      }
    } else {
      puts "[App] Router Not Yet Available"
    }
  }
}

# Now we can create a couple simple components and show the lifecycle hooks 
# being utilized.  We support most if not all the hooks given by the React 
# library and they work in a nearly identical fashion.

Component create Home {
  method componentWillUnmount {} {
    puts "Home Scene is being removed!"
  }
  method render {} {
    puts "Home Scene Renders!"
  }
}

Component create Login {

  # If we want to access props (from our parent) or state (from ourself)
  # we need to bring them into our scope (or call my variable in the method).
  variable STATE PROPS
  
  # Stateful Components are supported.  While generally state should 
  # come from the top-level and move down, we can use state to include 
  # and manage the state from our current component and its children.
  default_state {
    username {}
    password {}
  }
  
  method onInputChanged {key value} {
    puts "Input $key changed to : $value -- setting state and re-rendering"
    my setState [dict create $key $value]
  }
  
  method componentWillMount {} {
    puts "Login Scene will Mount Shortly!"
  }
  
  method componentDidMount {} {
    # While this is generally not something we would do, lets look at
    # what would happen when the TextInput updates its value
    puts "Login Scene Did Mount!"
    after 0 [callback my onInputChanged username "me@email.com"]
  }
  
  method componentWillUnmount {} {
    puts "Login Scene is being removed!"
  }
  
  method render {} {
    puts "Login Scene Renders!"
    *TextInput \
      key      username \
      label    "Username" \
      value    [dict get $STATE username] \
      onChange [callback my onInputChanged password]
    *TextInput \
      key      password \
      label    "Password" \
      value    [dict get $STATE password] \
      onChange [callback my onInputChanged password]
  }
  
}

Component create TextInput {
  variable PROPS
  
  # We can define default_props that will be used for any props 
  # that the user does not explicitly define.
  default_props {
    placholder "Enter Value"
    onChange   {}
    value      {}
  }
  
  method setValue { value } {
    # Just as an example of how we would set the value
    if { [dict exists $PROPS onChange] } {
      # This will call the onInputChanged method in our parent, resulting
      # in the state changing and re-rendering this component with the changed 
      # value (thus updating our UI).
      {*}[dict get $PROPS onChange] $value
    }
  }
  
  method render {} {
    puts "[dict get $PROPS label] Text Input Renders!"
    puts "Current Value: [dict get $PROPS value]"
    # We would render our UI / Widget / DOM here
  }
}


react render App

react dispatch SET_SCENE login
```

The results of running the above is:

```bash
App Renders!
Store | router {scene home}
Home Scene Renders!
Setting Scene to: login
App Renders!
Store | router {scene login}
Home Scene is being removed!
Login Scene will Mount Shortly!
Login Scene Renders!
Username Text Input Renders!
Current Value: 
Password Text Input Renders!
Current Value: 
Login Scene Did Mount!
Input username changed to : me@email.com -- setting state and re-rendering
Login Scene Renders!
Username Text Input Renders!
Current Value: me@email.com
```

One thing to note in the output above is that when we re-rendered our login scene 
due to updating the "username" state, only the username text input was re-rendered 
while any unchanged components are ignored.

Now this is missing a few key pieces such as updating the state using 
`my setState` (or even better, using the store to manage the state of the inputs). 
Hopefully it starts to paint a picture of how the package operates. 