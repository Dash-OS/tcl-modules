# A two-way valias which can be written from both ends and the variable will
# be changed completely.
proc valias {source alias} { tailcall upvar 0 $source $alias }