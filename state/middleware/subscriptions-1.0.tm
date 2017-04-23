####################
# State Middleware 
# 
#   The middleware mechanism provides an "extension" to the state.  These
#   middlewares are registered similar to state registration.  Once registered 
#   it may be attached to any state within the app by its name.
#
#   state register MyState {} { middlewares {logger subscriptions} ... }
#
#   Middlewares define at what point in the lifecycle they wish to be called.  In
#   most cases they will be expected to mutate values to their needs using upvar / uplevel.
####################

# snapshot 
# key integrationID set {integrationID ip state} items 
# {ip {value 192.168.1.10 prev 192.168.1.3} state {value 1 prev 0}} 
# changed {ip state} entryID 2 keys {ip state} refs 
# {entry ::Import::Modules::state::Containers::DeviceStream::Entries::2}

package require oo::module
package require list_tools
package require extend::dict
package require coro

# Build the subscriptions middleware so that we can attach it to the state
# as needed.
::state::register::middleware subscriptions ::state::middleware::subscriptions {} {
	api {
		method subscribe { localID args } {
			my variable subscription_containers
			lappend subscription_containers $localID
			[ my ref $localID ] subscribe [::state::parse::subscription $localID {*}$args]
		}
		method unsubscribe { localID {action {}} args } {
			my variable subscription_containers
			if { ! [info exists subscription_containers] } { return 0 }
			if { $action ni [list -kill -pause -resume] } {
				set args [list $action {*}$args]
				set action -kill
			}
			if { $localID eq "-all" } {
				foreach localID $subscription_containers {
					[ my ref $localID ] unsubscribe $action {*}$args
				}
			} else {
				[ my ref $localID ] unsubscribe $action {*}$args
			}
		}
	}
	container {
		method subscribe { subscription } {
			my variable MIDDLEWARES
			[dict get $MIDDLEWARES onSnapshot subscriptions] subscribe $subscription
		}
		method unsubscribe {action args} {
			my variable MIDDLEWARES
			switch -- $action {
				-kill {
					[dict get $MIDDLEWARES onSnapshot subscriptions] unsubscribe {*}$args
				}
				-pause {
					[dict get $MIDDLEWARES onSnapshot subscriptions] pause {*}$args
				}
				-resume {
					[dict get $MIDDLEWARES onSnapshot subscriptions] resume {*}$args
				}
			}
			
		}
	}
}

module create ::state::middleware::subscriptions {

	variable SUBSCRIPTIONS
	variable SUBSCRIPTION_MAP
	variable CONTAINER
	variable I
	variable EVALUATIONS
	variable CONFIG
	variable BATCH STATE
	
	constructor { container stateConfig middlewareConfig } {
		set CONTAINER $container
		if { [dict exists $stateConfig subscriptions] } {
			set CONFIG [dict get $stateConfig subscriptions]
			if { ! [dict exists $CONFIG bulk] && [dict exists $stateConfig bulk] } {
				dict set CONFIG bulk [dict get $stateConfig bulk]
			}
		} else { set CONFIG $stateConfig }
		set SUBSCRIPTIONS    [dict create]
		set SUBSCRIPTION_MAP [dict create]
		set EVALUATIONS      [dict create]
		set STATE            [dict create]
		set BATCH [expr { ! [dict exists $CONFIG batch] || [dict get $CONFIG batch] }]
		set I 0
		namespace eval Evaluators {}
		#every 5000 [callback my report]
	}
	
}

::oo::define ::state::middleware::subscriptions method report {} {
	dict for {k v} $EVALUATIONS {
		puts "$k"
		puts $v
		puts {}
	}
	puts $EVALUATIONS
}

::oo::define ::state::middleware::subscriptions method matches patterns {
	set matches [dict create]
	foreach pattern $patterns {
		set matches [dict merge $matches [dict filter $SUBSCRIPTION_MAP key $pattern]]
	}
	return $matches
}

::oo::define ::state::middleware::subscriptions method unsubscribe args {
	set matches [my matches $args]
	dict for { subscriptionID params } $matches {
		dict with params {}
		dict unset SUBSCRIPTIONS $type $priority $subscriptionID
		if { [dict exists $STATE $subscriptionID] } {
			dict unset STATE $subscriptionID	
		}
		dict unset SUBSCRIPTION_MAP $subscriptionID
	}
}

::oo::define ::state::middleware::subscriptions method pause args {
	set matches [my matches $args]
	dict for { subscriptionID params } $matches {
		dict with params {}
		if { ! [dict exists $SUBSCRIPTION_MAP $subscriptionID paused] } {
			dict set SUBSCRIPTIONS    $type $priority $subscriptionID paused 1
			dict set SUBSCRIPTION_MAP $subscriptionID paused 1	
		}
	}
}

::oo::define ::state::middleware::subscriptions method resume args {
	set matches [my matches $args]
	dict for { subscriptionID params } $matches {
		dict with params {}
		if { [dict exists $SUBSCRIPTION_MAP $subscriptionID paused] } {
			dict unset SUBSCRIPTIONS    $type $priority $subscriptionID paused
			dict unset SUBSCRIPTION_MAP $subscriptionID paused
		}
	}
}

::oo::define ::state::middleware::subscriptions method subscribe { subscription } {
	#puts $subscription
	if { [dict exists $subscription subscription id] } {
		set subscriptionID [dict get $subscription subscription id]
		dict unset subscription subscription id
	} else { set subscriptionID Sub_[incr I] }
	if { [dict exists $subscription subscription config async] } {
		set type [expr { [dict get $subscription subscription config async] 
			? "async"
			: "sync"
		}]
		dict unset subscription subscription config async
	} elseif { [dict exists $CONFIG async] } {
		set type [expr { [dict get $CONFIG async] 
			? "async"
			: "sync"
		}]
	} else { set type "async" }
	
	if { [dict exists $subscription subscription config state] && [dict get $subscription subscription config state] } {
		# Stateful Subscription requested
		dict set STATE $subscriptionID [dict create]
	}
	if { [dict exists $subscription subscription config priority] } {
		# A priority value allows the user to assign a priority to when specific
		# subscriptions should be evaluated over another.
		set priority [dict get $subscription subscription config priority]
	} else { 
		# Values with no priority will be set to a priority of 10.
		set priority 10
	}
	if { [dict exists $SUBSCRIPTIONS $type] } {
		set new 0
		set subscription_type [dict get $SUBSCRIPTIONS $type]	
	} else { 
		set new 1
		set subscription_type [dict create] 
	}
	if { ! [dict exists $subscription_type $priority] } {
		# When the priority is not new we do not need to run a dict sort on the
		# value.
		set sort 1
	} else {  set sort 0 }
	
	dict set subscription_type $priority $subscriptionID $subscription
	
	if { $sort } {
		# We have indicated that we want to sort the dict by its priority
		set subscription_type [dict sort keys $subscription_type]
	}
	#puts setting
	#puts $subscription_type
	dict set SUBSCRIPTIONS $type $subscription_type
	dict set SUBSCRIPTION_MAP $subscriptionID [dict create \
		type     $type \
		priority $priority
	]
}
	
	
# Cleanup any evaluations and evaluators
::oo::define ::state::middleware::subscriptions method finished { keyValue {evalID {}} } {
	if { $evalID eq {} } {
		dict for { evalID evalSchema } [dict get $EVALUATIONS $keyValue] {
			my cancelEvaluation $keyValue $evalID
		}
	} else {
		my cancelEvaluation $keyValue $evalID
	}
	if { [string equal [dict get $EVALUATIONS $keyValue] {}] } {
		dict unset EVALUATIONS $keyValue
	}
}

# Cancel the evaluation and cleanup any data which is associated with a 
# specific context (EVALUATIONS).
::oo::define ::state::middleware::subscriptions method cancelEvaluation { keyValue {evalID {}} } {
	if { 
			 $evalID ne "async"
		&& [dict exists $EVALUATIONS $keyValue async evalID] 
		&& [dict get $EVALUATIONS $keyValue async evalID] eq $evalID 
	} { my cancelEvaluation $keyValue async }
	
	if { ! [dict exists $EVALUATIONS $keyValue $evalID] } { return }
	
	set evaluation [dict get $EVALUATIONS $keyValue $evalID]
	dict unset EVALUATIONS $keyValue $evalID
	
	if { [dict exists $evaluation asyncID] } {
		after cancel [dict get $evaluation asyncID]
	}
	if { [dict exists $evaluation evaluator] } { 
		set evaluator [dict get $evaluation evaluator]
		if { [info commands $evaluator] ne {} } { rename $evaluator {} }
	}

	if { $evalID eq "async" && [dict exists $evaluation evalID] } {
		my cancelEvaluation $keyValue [dict get $evaluation evalID]
	}
}

::oo::define ::state::middleware::subscriptions method onDestroy args {
	puts $EVALUATIONS
	if { [info exists EVALUATIONS] } {
		foreach keyValue [dict keys $EVALUATIONS] {
			dict for { evalID evalSchema } [dict get $EVALUATIONS $keyValue] {
				my cancelEvaluation $keyValue $evalID
			}
		}
	}
}

# Evaluate is called by the middleware processor whenever a new snapshot is 
# available to parse.  In this case we need to evaluate our subscriptions to
# determine if we should execute any subscribed commands.
#
# Evaluation is highly optimized based on the configuration settings used when 
# registering a state.  By default, a synchronous subscription will always build
# a new evaluation context which it uses to evaluate the snapshot.  
#
# Asynchronous evaluations may be evaluated in a variety of ways depending on the 
# configuration.  If we registered our state with the "batch" option (default) then 
# each new snapshot that occurs will be merged with the previous until an evaluation
# has a chance to occur (event loop resolves).  
#
# Before an evaluation occurs, we will first synchronously filter the subscriptions for
# both the sync and async evaluations.  If no subscriptions match our filter, the subscriptions 
# will not be evaluated.  If we have an async batched evaluation which eventually does not 
# match our newly merged snapshot then its evaluation will be cancelled immediately.	
::oo::define ::state::middleware::subscriptions method onSnapshot { snapshot } {
	try {	
		# Start the evaluator coroutine 
		if { [string equal $SUBSCRIPTIONS [dict create]] } { return }
		set keyValue   [dict get $snapshot keyValue]
		set evalSchema [dict create]
		set evalID Evaluators::E_[incr I]
		set hasSync  [dict exists $SUBSCRIPTIONS sync]
		set hasAsync [dict exists $SUBSCRIPTIONS async]
		if { $hasSync } {
			dict set evalSchema evaluator [my BuildEvaluator $evalID $snapshot]
		}
		if { $hasAsync } {
			if { $BATCH && [dict exists $EVALUATIONS $keyValue async] } {
				set asyncEvaluator [dict get $EVALUATIONS $keyValue async evaluator]
				#set batchedEvalIDs [dict get $EVALUATIONS $keyValue async batchedEvalIDs]
				if { [string equal $asyncEvaluator [info coroutine]] } {
					# This happens when we are inside of the evaluator context and we are
					# calling the onSnapshot.  In this case we need to use after so that 
					# we allow the coroutine to continue its evaluation.
					tailcall after 0 [namespace code [list my onSnapshot $snapshot]]
				}
				set asyncSnapshot [my batch $snapshot $keyValue]
				set asyncEvalID   [dict get $EVALUATIONS $keyValue async evalID]
			} else { 
				set asyncSnapshot $snapshot
				#if { $BATCH } { set asyncEvalID async } else { set asyncEvalID $evalID }
				set asyncEvalID $evalID
				if { [dict exists $evalSchema evaluator] } {
					# We will use the same evaluator that is used by the synchronous evaluation
					# in this case.  This evaluator will then stay around until a batched evaluation
					# concludes.  Any synchronous evaluations in-between will cause the synchronous 
					# evaluation to occur in a new context, however, the asynchronous evaluation will 
					# continue in the original evaluator so that we can use our merged snapshot for 
					# the final evaluation.
					set asyncEvaluator [dict get $evalSchema evaluator]	
				} else {
					# We need to build a new evaluator if it wasn't created already.  This
					# will generally mean its a new asynchronous evaluation and we do not 
					# have any synchronous subscriptions.  We build the evaluator in this
					# case as-if we did so that we will automatically instatiate the 
					# evaluator later.
					set asyncEvaluator [my BuildEvaluator $evalID $snapshot]
					dict set evalSchema evaluator $asyncEvaluator
				}
			}
			if { $asyncSnapshot ne "kill" } {
				
				# We need to provide the asyncEvalID to the synchronous evaluator (if it exists)
				# so that it will know whether or not it should delete the evaluator or not.
				if { $BATCH } {
					set asyncID [ after 0 [namespace code [list my search async {} $asyncSnapshot $keyValue async]] ]
					#lappend batchedEvalIDs $evalID
					dict set EVALUATIONS $keyValue async [dict create \
						evalID    $asyncEvalID \
						asyncID   $asyncID \
						evaluator $asyncEvaluator
					]
				} else {
					set asyncID [ after 0 [namespace code [list my search async {} $asyncSnapshot $keyValue $asyncEvalID]] ]
				}
				dict set evalSchema asyncEvalID $asyncEvalID
			} else { puts KILLED ; set hasAsync 0 }
		}

		# Evaluator may be set & created in various ways, but if it exists, we know
		# we have a newly generated evaluator and we need to instatiate it.
		if { [dict exists $evalSchema evaluator] } {
			# We need to save the value if we either have a synchronous evaluation or if 
			# we have an asynchronous evaluation and we are not batching the requests.  
			if { $hasSync || ! $BATCH } {
				# Set the evalSchema onto EVALUATIONS before we evaluate the synchronous 
				# requests.
				dict set EVALUATIONS $keyValue $evalID $evalSchema
			}
			# If we are using a newly created evaluator we need to call it for the first
			# time to initiate it.
			[dict get $evalSchema evaluator]
		}
		
		if { $hasSync } {
			set filtered [ my filter sync $snapshot $keyValue $evalID ]
			if { ! [string equal $filtered {}] } {
				my search sync $filtered $snapshot $keyValue $evalID
			} elseif { ! $hasAsync } {
				# If we don't have any async evaluations we will cancel the evaluation 
				# which cleans up the EVALUATIONS state.
				my finished $keyValue $evalID	
			}
		}
	} on error {result options} {
		::onError $result $options "While Evaluating a Snapshot for State $CONTAINER"
	}
}


	
::oo::define ::state::middleware::subscriptions method BuildEvaluator { evalID snapshot } {
	return [coroutine $evalID rule_evaluator $snapshot]
}

::oo::define ::state::middleware::subscriptions method inject { evaluator script } {
	::tcl::unsupported::inject $evaluator try $script
	tailcall $evaluator
}

# Batching is an optimization technique which we use by default.  This
# will merge evaluations that occur within the same event loop so that 
# we only end up evaluating once with the most up-to-date value of 
# the state when our evaluation methods continue.  
#
# There are times this may be undesireable as we may want to evaluate
# and execute for each successive change no matter what.  In this case
# it can be turned off by changing "batch" to 0 in the states registration.
#
# This is done by injecting a command into our snapshot evaluator which will 
# refresh the closure with the new data merged with the old.  It will then
# return the merged snapshot to us which we can use to then schedule the 
# next evaluation.
::oo::define ::state::middleware::subscriptions method batch { snapshot keyValue } {
	set evalSchema [dict get $EVALUATIONS $keyValue async]
	if { [dict exists $evalSchema asyncID] } {
		# Cancel the scheduled evaluation as we need to reschedule with our 
		# newly merged snapshot value instead.
		after cancel [dict get $evalSchema asyncID]	
	}
	set evaluator [dict get $evalSchema evaluator]
	my inject $evaluator {
  	set rule [ yield ]
  	set items [dict merge $items [dict get? $rule items]]
  	foreach e [dict get? $rule removed] { 
			set keys    [lsearch -all -inline -not -exact $keys    $e]
			set set     [lsearch -all -inline -not -exact $set     $e]	
			set changed [lsearch -all -inline -not -exact $changed $e]
			if { $e in $created } {
				# If an item is removed that was created since the last eval then 
				# we remove any trace that it ever existed in the first place.
				if { $keyID eq $e } {
					# If the entire key is being removed then we have no reason to 
					# even evaluate this subscription anymore.  In this case we will
					# kill the entire evaluation process.
					yield kill
				} else {
					dict unset items $e
					set created [lsearch -all -inline -not -exact $created $e]
				}
			} else {
				if { $e ni $removed } { lappend removed $e }
				# if { [dict exists $items $e] } {
				# 	dict set items $e [dict create value {} prev [dict get $items $e value]]	
				# }
			}
		}
		if { $keyID in $removed } { set entry_removed 1 } else { set entry_removed 0 }
		foreach e [dict get? $rule set] {
			if { ! [info exists set] } {
				lappend set $e	
			} elseif { $e ni $set } {
				lappend set $e
			}
		}
		foreach e [dict get? $rule created] { 
			lappend keys    $e
			lappend created $e
			set removed [lsearch -all -inline -not -exact $removed $e]
			dict set items $e [dict get? $rule items $e]
		}
		foreach e [dict get? $rule changed] {
 			if { $e ni $changed } { lappend changed $e }
		}
		set snapshot [dict merge $rule [dict create \
  		keys $keys set $set changed $changed \
  		created $created items $items  removed $removed
  	]]
  	set rule [yield $snapshot]
  }
  return [ $evaluator $snapshot ]
}

# We apply a dict filter to the subscriptions at initial evaluation for both
# sync and async subscriptions.  We then only evaluate subscriptions which 
# have a chance of passing its evaluation.
#
# Specifically we are making sure that all active keys are apart of the 
# snapshot and the entry has all the keys that the subscription expects.
::oo::define ::state::middleware::subscriptions method filter { type snapshot keyValue evalID } {
	# We have to run by priority - which we should have already been sorted by
	set subscriptions [dict create]
	#puts $SUBSCRIPTIONS
	dict for { priority subs } [dict get $SUBSCRIPTIONS $type] {
		dict for { id subscription } $subs {
			#puts $subscription
			if { [dict exists $subscription paused] } { continue }
			set i 0
			# actives is a list where each element will represent the the active
    	# keys for a specific "or" value.  We will remove any which should not
    	# be evaluated and only return a subscription at all if it has at least
    	# one "or" value which could possibly evaluate to true.
			set actives [dict get $subscription subscription active]
			set ors     [dict get $subscription subscription ors]
			
    	foreach active $actives {
    		if { 
    			   $active ne "*" && $active ne {} 
    			&& ! [ lhas $active [concat [dict get? $snapshot set] [dict get? $snapshot removed]] ] 
    		} {
    			# The subscription does not match, we want to remove the value from the 
    			# subscription that we will return in this case.
    			set actives [lreplace $actives[set actives {}] $i $i]
    			set ors     [lreplace $ors[set ors {}] $i $i]
    		} else { incr i }
    	}
    	if { $ors ne {} } {
    		# If any $ors remains then we want to update the subscriptions dictionary
    		# and pass it for evaluation.
    		dict set subscriptions $id $subscription
    		dict set subscriptions $id subscription active $actives
    		dict set subscriptions $id subscription ors $ors
    	} else { dict unset subscriptions $id }
		}
	}
	return $subscriptions
}

::oo::define ::state::middleware::subscriptions method evaluateRules { or subscription snapshot keyValue evalID } {
	set result 0
	foreach rule $or {
		if { [string trim $rule] eq {} } { continue }
		lassign [ [dict get $EVALUATIONS $keyValue $evalID evaluator] $rule ] result items
		#puts "Evaluation Result: $result"
		if { ! $result } { break }
	}
	return $result
}

::oo::define ::state::middleware::subscriptions method search { type subscriptions snapshot keyValue evalID } {
	if { $type eq "async" } { 
		set subscriptions [ my filter async $snapshot $keyValue $evalID ]
	}
	dict for {subscriptionID subscriptionSchema} $subscriptions {
		set subscription [dict get $subscriptionSchema subscription]
		unset -nocomplain passed
		foreach or [dict get $subscription ors] {
			if { [my evaluateRules $or $subscription $snapshot $keyValue $evalID] } {
				set passed 1
				break
			}
		}
		if { [info exists passed] } {
			unset passed
			# When a subscription passes, we need to execute the provided script statement.
			# We want to do this within the context of our evaluator so that they have access 
			# to all the variables used internally  within the statement itself.  While this 
			# is more difficult as the variable names can not be defined, it provides much faster
			# evaluation without having to substitute all the values internally.
			# 
			# For performance, and to stop from polluting the con
			set evaluator [dict get $EVALUATIONS $keyValue $evalID evaluator]
			my inject $evaluator {
				lassign [ yield ] subscriptionSchema STATE
				set setters [dict get $subscriptionSchema subscription setters]
				try [dict get $subscriptionSchema script] on error {result options} {
					::onError $result $options "While Running a Subscription" $subscriptionSchema
				}
				set rule [ yield $STATE ]
				unset -nocomplain subscriptionSchema
				unset -nocomplain STATE
			}
			# Now that we have injected the execution, we need to pass the evaluator our subscription
			# so that it can execute the script as required.
			#
			# Since the execution is actually done within the context of our evaluator, its also
			# important to note that modifying the included locals will cause the evaluator to 
			# use the new values during evaluation.  This allows a subscription to modify other
			# subscriptions and can be dangerous.  In general a subscription should quickly execute
			# another script to avoid this. -- This does not appear to be true anymore...
			#
			# Also we should avoid setting variables here for the most part.  One interesting benefit
			# could be to use the shared context as a method to share state between subscriptions which 
			# are executed by the same snapshot / evaluation.
			if { [dict exists $STATE $subscriptionID] } {
				set stateful 1	
				set state [dict get $STATE $subscriptionID]
			} else { 
				set stateful 0 
				set state {}
			}
			set state [ $evaluator [list $subscriptionSchema $state] ]
			if { $stateful } { dict set STATE $subscriptionID $state }
			$evaluator
		}
	}
	if { $type eq "async" } { my finished $keyValue $evalID } else { 
		# When a synchronous evaluation has completed, we need to check to
		# see if it is safe to remove / cleanup the evaluator and associated
		# data.  There may be an asynchronous evaluation that is depending
		# upon the evaluator.
		if {
				   ! [dict exists $EVALUATIONS $keyValue $evalID asyncEvalID]
				|| [dict get $EVALUATIONS $keyValue $evalID asyncEvalID] ne $evalID
		} { my finished $keyValue $evalID } else {
			# puts "Asynchronous Snapshot Using $evalID"
		}
	}
}
	
	
# Our Rule Evaluator provides an evaluation context for our rule evaluations.  This is largely 
# meant to increase the speed at-which we can evaluate our rules.  We do this by maintaining a 
# closure with the results of each subscriptions needs that will be constant.  
#
# This means that we will query for new items when required only and if say 200 subscriptions 
# are on a state, for the life of the evaluation of those 200 subscriptions we will only need 
# to query the values a maximum of one time.
# ::tcm::module::state-subscription-middleware::
proc ::state::middleware::subscriptions::rule_evaluator snapshot {
	set STATE {}
	dict with snapshot {}
	if { [info exists keyValue] } { set entry_id $keyValue }
	set result 0
	set entry_removed 0
	set value {} ; set prev {}
	yield [info coroutine]
	while 1 {
		try {
			set rule [yield [list $result $items]]
			if { $rule eq {} } { continue }
			set result 0
			dict with rule {}
			if { ! [dict exists $items $key] && $key ne "*" } {
				if { $key in $keys } {
					if { [dict exists $snapshot refs entry] } {
						dict set items $key [dict get? [[dict get $snapshot refs entry] get SNAPSHOT $key] $key]
					}
				}
			}
			set item [dict get? $items $key]
			if { $key eq "*" || $item ne {} } {
				dict with item {}	
				try {
					if { [dict exists $modifiers before-eval] } {
						foreach modifier [dict get $modifiers before-eval] {
							try $modifier 
						}	
					}
					set result [try $evaluate]
					if { [dict exists $modifiers after-eval] } {
						foreach modifier [dict get $modifiers after-eval] {
							try $modifier
						}	
					}
				} on error {_result _options} {
					puts "Error: ${_result}"
					::onError ${_result} ${_options} "While Running a Subscription Execution" 
				}
			} else { set result 0 }
		} on error {_result _options} {
			::onError ${_result} ${_options} "While Evaluating a Subscription Rule"
			set result 0
		}
	}
}
