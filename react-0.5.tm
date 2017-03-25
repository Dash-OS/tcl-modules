package require oo::metaclass

# Currently we need to redefine the metaclass unknown definition to handle our
# component resolution.  This way we can internally handle creation and deletion

proc ::oo::metaclass::unknown {self what args} {
  if { [string equal [string index $what 0] *] } {
    # Our Modifications to metaclasses unknown
    uplevel 1 [list \
      [uplevel 1 {namespace current}]::my \
      @@RenderChild \
      [uplevel 1 [list namespace which [string range $what 1 end]]] \
      {*}$args
    ]
  } else {
    # The original metaclass unknown
    if { $what in [info object methods $self -all] } {
      tailcall $self $what {*}$args
    } elseif { [list ::oo::define::$what] in [info commands ::oo::define::*] } {
      tailcall ::oo::define $self $what {*}$args
    } else { tailcall ::unknown $what {*}$args }
  }
}

  
namespace eval ::React {}

proc react { cmd args } {
  switch -- $cmd {
    render {
      set args [ lassign $args component ]
      if { [info commands $component] eq {} } {
        set component [uplevel 1 [list namespace which $component]]
        if { [info commands $component] eq {} } {
          throw error "$component is not a known component"
        }
        
      }
      set root [ $component create ::React::Root [dict create order 0 root 1] {*}$args ]
    }
  }
}

::oo::class create ::React::ComponentMixin {
  variable @@COMPONENT PROPS STATE
  
  constructor {context args} {
    set STATE       [dict create]
    set PROPS [dict merge [my static default_props] [lindex $args 0]]
    set @@COMPONENT [dict create]
    dict set @@COMPONENT status disable_state_rerender 1
    if { [self next] ne {} } { next {*}$args }
    dict unset @@COMPONENT status disable_state_rerender
    
    my componentWillMount
    my @@Render
    my componentDidMount
  }
  
  method static {cmd args} {
    tailcall [namespace parent]::my $cmd {*}$args
  }
  
  method @namespace {} { return [namespace current] }
  
  method @@RenderChild { C args } {
    set component [set @@COMPONENT]
    if { ! [dict exists $component status rendering] } {
      my @@Log "You may only render children during a render"
      return 0
    }
    set child [dict get $component render_child]
    if { ! [dict exists $args key] } {
      #my @@Log "Each child must have a unique key.  The key must be unique to all children of the component"
      #return 0
      set key auto_$child
    } else {
      set key [dict get $args key]
      dict unset args key
    }
    if { [dict exists $component c $key] } {
      dict lappend @@COMPONENT render_queue [list [my @@Child $key]::my setProps $args]
    } else {
      dict lappend @@COMPONENT render_queue [join [list \
        [subst -nocommands { set _component [$C create [self]::c::$key {o {$child}} {$args}] }] \
        [format { dict set @@COMPONENT c {%s} ${_component} } $key ] \
      ] \;]
    }
    dict lappend @@COMPONENT rendered $key
    dict incr @@COMPONENT render_child
  }
  
  method @@CompleteRender {} {
    set component [set @@COMPONENT]
    if { [dict exists $component render_queue_id] } {
      after cancel [dict get $component render_queue_id]
      dict unset @@COMPONENT render_queue_id
    }
    if { [dict exists $component render_queue] } {
      set render_queue [dict get $component render_queue]
      foreach queued $render_queue {
        try $queued
      }
      dict unset @@COMPONENT render_queue
    }
  }
  
  # Internal method that we call when we want to start a render process.
  method @@Render {} {
    # We do this as a workaround of the bug 
    # http://core.tcl.tk/tcl/tktview/900cb0284bcf1bf27038a7ae02c9f1440b150c86
    if { [my render 1] eq {} } { 
      return
    }
    dict set @@COMPONENT status rendering 1
    dict set @@COMPONENT render_child 0
    try { my render } on error {result options} {
      my @@Log "An Error Occurred During Render: $result"
    }
    set component [set @@COMPONENT]
    if { [dict exists $component rendered] && [dict exists $component c] } {
      foreach rendered [dict get $component rendered] {
        dict unset component c $rendered
      }
      my @@UnmountChildren [dict get $component c]
    } elseif { [dict exists $component c] } {
      my @@UnmountChildren [dict get $component c]
    }
    my @@CompleteRender
    dict unset @@COMPONENT render_child
    dict unset @@COMPONENT status rendering
    dict unset @@COMPONENT rendered
  }
  
  method @@Child { key } {
    return [ [self]::c::${key} @namespace ]
  }
  
  method @@UnmountChildren { children } {
    dict for { key child_num } $children {
      [my @@Child $key]::my componentWillUnmount
      dict unset @@COMPONENT c $key
    }
  }
  
  method @@Log msg {
    set msg "[my static display_name] | [self] | $msg"
    puts stderr $msg
    return $msg
  }
  
  # my setState $state 
  #   Performs a shallow merge of nextState into current state. This is the primary 
  #   method you use to trigger UI updates from event handlers and server request 
  #   callbacks.
  # 
  #   setState does not immediately mutate this.state but creates a pending state 
  #   transition. Accessing this.state after calling this method can potentially 
  #   return the existing value.
  method setState { state } {
    set component [set @@COMPONENT]
    if { [dict exists $component status disable_state_rerender] } {
      set rerender 0
    } else { 
      if { [dict exists $component status disable_set_state] } {
        throw error "[my static display_name] | You may not set state from within a render or update lifecycle, this will cause an endless loop"
      } else {
        set rerender 1  
      }
    }
    if { [dict exists $component next_state] } {
      dict set @@COMPONENT next_state [dict merge \
        [dict get $component next_state] \
        $state
      ]
    } else { 
      dict set @@COMPONENT next_state $state
    }
    if { $rerender && ! [dict exists $component queued_update] } {
      dict set @@COMPONENT queued_update [ after 0 \
        [namespace code [list my shouldComponentUpdate]]
      ] 
    }
  }
  
  method setProps { props } {
    set component [set @@COMPONENT]
    if { [dict exists $component next_props] } {
      set next_props [dict merge \
        [dict get $component next_props] \
        $props
      ] 
    } else { set next_props $props }
    if { $next_props ne $PROPS } { 
      dict set @@COMPONENT next_props $next_props  
      if { ! [dict exists $component queued_props_update] } {
        dict set @@COMPONENT queued_props_update [ after 0 \
          [namespace code [list my componentWillReceiveProps]]
        ]
      }
    } else {
      if { [dict exists $component queued_props_update] } {
        after cancel [dict get $component queued_props_update]
        dict unset @@COMPONENT queued_props_update
      }
      if { [dict exists $component next_props] } {
        dict unset @@COMPONENT next_props 
      }
    }
  }
  
  # When we want to check if we should update the component, this will be called.
  # If our child has the method defined then we will use their response to determine
  # if we should update.  Otherwise we will simply update.
  #
  # -- When defined in the component:
  # Use shouldComponentUpdate() to let React know if a component's output is not affected 
  # by the current change in state or props. The default behavior is to re-render on 
  # every state change, and in the vast majority of cases you should rely on the default 
  # behavior.
  method shouldComponentUpdate { {force 0} } {
    dict set @@COMPONENT disable_set_state 1
    set component [set @@COMPONENT]
    
    set prev_props $PROPS ; set prev_state $STATE
    
    if { [dict exists $component queued_update] } {
      after cancel [dict get $component queued_update]
      dict unset @@COMPONENT queued_updated
    }
    
    if { [dict exists $component queued_props_update] } {
      after cancel [dict get $component queued_props_update]
      dict unset @@COMPONENT queued_props_update
    }
    
    if { [dict exists $component next_state] } {
      set next_state [dict merge $STATE [dict get $component next_state]] 
      dict unset @@COMPONENT next_state
    } else { set next_state $STATE }
    
    if { [dict exists $component next_props] } {
      set next_props [dict merge $PROPS [dict get $component next_props]] 
      dict unset @@COMPONENT next_props
    } else { set next_props $PROPS }
    
    # Have the props or state changed during this update?  If the net result
    # does not have any changed values then we won't even call the child.
    if { $force || $next_props ne $PROPS || $next_state ne $STATE } {
      if { ! $force && [self next] ne {} } { 
        if { [ string is true -strict [next $next_props $next_state] ] } { 
          set update 1
        }
      } else { set update 1 }
      if { [info exists update] } {
        # If we will update / call render then we will call componentWillUpdate
        # if it is defined with the new props and state.
        my componentWillUpdate $next_props $next_state
      }
      # Regardless we change the state and props if the values were changed
      set STATE $next_state
      set PROPS $next_props
    } else { return }
    
    # Should we call the render method?
    if { [info exists update] } { 
      my @@Render
      my componentDidUpdate $prev_props $prev_state
    }
    # Ok, we can now allow updating of state again!
    dict unset @@COMPONENT status disable_set_state
  }
  
  # componentWillUpdate() is invoked immediately before rendering when new props or 
  # state are being received. Use this as an opportunity to perform preparation before 
  # an update occurs. This method is not called for the initial render.
  method componentWillUpdate { next_props next_state } {
    if { [self next] ne {} } { catch { next $next_props $next_state } }
  }
  
  # componentDidUpdate() is invoked immediately after updating occurs. This method 
  # is not called for the initial render.
  method componentDidUpdate { prev_props prev_state } {
    if { [self next] ne {} } { catch { next $prev_props $prev_state } }
  }

  # componentWillUnmount() is invoked immediately before a component is unmounted and 
  # destroyed. Perform any necessary cleanup in this method, such as invalidating timers, 
  # canceling network requests, or cleaning up any DOM elements that were created in 
  # componentDidMount
  method componentWillUnmount {} {
    set component [set @@COMPONENT]
    if { [dict exists $component c] } {
      my @@UnmountChildren [dict get $component c]
    }
    if { [self next] ne {} } { catch { next } }
    [self] destroy
  }
  
  # componentWillMount() is invoked immediately before mounting occurs. It is called 
  # before render(), therefore setting state in this method will not trigger a 
  # re-rendering. Avoid introducing any side-effects or subscriptions in this method.
  method componentWillMount {} {
    if { [self next] ne {} } { next }
  }
  
  method componentDidMount {} {
    if { [self next] ne {} } { next }
  }
  
  # componentWillReceiveProps() is invoked before a mounted component receives new props. 
  # If you need to update the state in response to prop changes (for example, to reset it), 
  # you may compare this.props and nextProps and perform state transitions using this.setState() 
  # in this method.
  method componentWillReceiveProps {} {
    set component [set @@COMPONENT]
    if { [dict exists $component next_props] } {
      if { [self next] ne {} } { 
        dict set @@COMPONENT status disable_state_rerender 1
        catch { next [dict get $component next_props] }
        dict unset @@COMPONENT status disable_state_rerender
      }
      my shouldComponentUpdate
    }
  }
  
  method render { {check 0} } {
    if { $check } { return [self next] }
    if { [self next] ne {} } { next }
  }
  
  
  # By default, when your component's state or props change, your component will 
  # re-render. If your render() method depends on some other data, you can tell 
  # React that the component needs re-rendering by calling forceUpdate().
  method forceUpdate {} { 
    # set component [set @@COMPONENT]
    # if { [dict exists $component queued_update] } {
    #   after cancel [dict get $component queued_update]
    # }
    # dict set @@COMPONENT queued_update [after 0 \
    #   [namespace code [list my shouldComponentUpdate 1]]
    # ]
    my shouldComponentUpdate 1
  }
  
  # method render {} {
  #   if { [self next] ne {} } { next }
  # }
  
  # Do not allow outside calls of our lifecycle methods
  unexport render shouldComponentUpdate componentDidUpdate \
           componentDidMount componentWillMount setState \
           componentWillUnmount componentWillUpdate \
           componentWillReceiveProps forceUpdate setProps \
           destroy
  
  # Used to get the objects namespace.  This is how we override
  # and call the lifecycle methods as necessary from the parent.
  export   @namespace
  
}

# Our Component metaclass handles the internal syntax and static values
# capabilities. 
::oo::metaclass create Component {

  constructor data {
    next [join [list $data {
      mixin -append ::React::ComponentMixin
    } \;]]
  }
  
  method default_props { {props {}} } {
    my variable default_props
    if { [info exists default_props] } {
      return $default_props
    } elseif { $props ne {} } {
      set default_props [dict create {*}$props]
    }
  }
  
  method display_name { {name {}} } {
    my variable display_name
    if { [info exists display_name] || $name eq {} } {
      return [expr { [info exists display_name] 
        ? $display_name
        : [uplevel 1 {self}]
      }]
    } elseif { $name ne {} } {
      set display_name $name
    }
  }
  
  method static { prop {to {}} } {
    my variable $prop
    if { $to ne {} } {
      set $prop $to
    } elseif { [info exists $prop] } { return [set $prop] }
  }
  
  method ref { key } {
    return c::$key
  }
  
}
