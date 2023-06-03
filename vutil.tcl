# vutil.tcl
################################################################################
# Utilities for working with variables in Tcl

# Copyright (C) 2023 Alex Baker, ambaker1@mtu.edu
# All rights reserved. 

# See the file "LICENSE" for information on usage, redistribution, and for a 
# DISCLAIMER OF ALL WARRANTIES.
################################################################################

# Dependencies
package require errm 0.5

# Define namespace
namespace eval ::vutil {
    # Exported Commands
    namespace export pvar; # Print variables and their values
    namespace export local; # Access local namespace variables (like global)
    namespace export default; # Set a variable if it does not exist
    namespace export lock unlock; # Hard set a Tcl variable
    namespace export tie untie; # Tie a Tcl variable to a Tcl object
    namespace export link unlink; # Create an object variable
    namespace export obj type new; # Object variable class and types
}

# pvar --
#
# Same idea as parray. Prints the values of a variable to screen.
#
# Syntax:
# pvar $varName ...
#
# Arguments:
# $varName ...      Names of variable to print

proc ::vutil::pvar {args} {
    puts [uplevel 1 [list ::vutil::PrintVars {*}$args]]
}

# PrintVars --
#
# Private procedure for testing (returns what is printed with "pvar")

proc ::vutil::PrintVars {args} {
    foreach varName $args {
        upvar 1 $varName var
        if {![info exists var]} {
            return -code error "can't read \"$varName\": no such variable"
        } elseif {[array exists var]} {
            foreach {key value} [array get var] {
                lappend varList [list "$varName\($key\)" = $value]
            }
        } else {
            lappend varList [list $varName = $var]
        }
    }
    join $varList \n
}

# local --
#
# Define variables local to the namespace of the procedure or code.
# Simply calls "variable" multiple times in the calling scope.
#
# Syntax:
# local $varName ...
#
# Arguments:
# varName       Variable to access within namespace.

proc ::vutil::local {args} {
    foreach varName $args {
        uplevel 1 [list variable $varName]
    }
    return
}

# default --
#
# Soft set of a variable. Only sets the variable if it does not exist.
#
# Syntax:
# default $varName $value
#
# Arguments:
# varName       Variable name
# value         Variable default value

proc ::vutil::default {varName value} {
    upvar 1 $varName var
    if {![info exists var]} {
        set var $value
    } else {
        set value $var
    }
    return $value
}

# lock --
#
# Hard set of a variable. locked variables cannot be modified by set or default
#
# Syntax:
# lock $varName <$value>
#
# Arguments:
# varName       Variable to lock
# value         Value to set

proc ::vutil::lock {varName args} {
    upvar 1 $varName var
    # Switch for arity (allow for self-tie)
    if {[llength $args] == 0} {
        if {[info exists var]} {
            set value $var
        } else {
            return -code error "can't read \"$varName\": no such variable"
        }
    } elseif {[llength $args] == 1} {
        set value [lindex $args 0]
    } else {
        ::errm::wrongNumArgs "lock varName ?value?"
    }
    # Remove any existing lock trace
    if {[info exists var]} {
        unlock var
    }
    # Set value and define lock trace
    set var $value
    trace add variable var write [list ::vutil::LockTrace $value]
    return $value
}

# unlock --
#
# Unlock defined variables
#
# Syntax:
# unlock $varName ...
#
# Arguments:
# varName...    Variables to unlock

proc ::vutil::unlock {args} {
    foreach varName $args {
        upvar 1 $varName var
        if {![info exists var]} {
            return -code error "can't unlock \"$varName\": no such variable"
        }
        set value $var; # Current value
        trace remove variable var write [list ::vutil::LockTrace $value]
    }
    return
}

# LockTrace --
#
# Private procedure, used for enforcing locked value
#
# Syntax:
# LockTrace $value $varName $index $op
#
# Arguments:
# value         Value to lock
# varName       Variable (or array) name
# index         Index of array if variable is array
# op            Trace operation (unused)

proc ::vutil::LockTrace {value varName index op} {
    upvar 1 $varName var
    if {[array exists var]} {
        set var($index) $value
    } else {
        set var $value
    }
}

# TCLOO GARBAGE COLLECTION
################################################################################

# tie --
# 
# Tie a variable to a Tcl object, such that when the variable is modified or
# unset, by unset or by going out of scope, that the object is destroyed as well
# Overrides locks. 
#
# Syntax:
# tie $varName <$object>
#
# Arguments:
# varName       Variable representing object
# objName       Name of Tcl object

proc ::vutil::tie {varName args} {
    upvar 1 $varName refVar
    # Switch for arity (allow for self-tie)
    if {[llength $args] == 0} {
        if {[info exists refVar]} {
            set objName $refVar
        } else {
            return -code error "can't read \"$varName\": no such variable"
        }
    } elseif {[llength $args] == 1} {
        set objName [lindex $args 0]
    } else {
        ::errm::wrongNumArgs "tie varName ?objName?"
    }
    # Verify object
    if {![info object isa object $objName]} {
        return -code error "\"$objName\" is not an object"
    }
    # Remove any existing lock and tie traces
    if {[info exists refVar]} {
        unlock refVar
        untie refVar
    }
    # Set the value of the variable and add TieTrace
    set refVar $objName
    trace add variable refVar {write unset} [list ::vutil::TieTrace $objName]
    # Return the value (like with "set")
    return $objName
}

# untie --
# 
# Untie variables from their respective Tcl objects.
#
# Syntax:
# untie $varName ...
#
# Arguments:
# varName...    Variables to unlock

proc ::vutil::untie {args} {
    foreach varName $args {
        upvar 1 $varName refVar
        if {![info exists refVar]} {
            return -code error "can't untie \"$varName\": no such variable"
        }
        set objName $refVar
        trace remove variable refVar {write unset} \
                [list ::vutil::TieTrace $objName]
    }
    return
}

# TieTrace --
#
# Destroys associated Tcl object and removes ties
#
# Syntax:
# TieTrace $objName $varName $index $op
#
# Arguments:
# varName       Variable (or array) name
# index         Index of array if variable is array
# op            Trace operation (unused)

proc ::vutil::TieTrace {objName varName index op} {
    catch {$objName destroy}; # try to destroy object
    upvar 1 $varName refVar
    if {[info exists refVar]} {
        if {[array exists refVar]} {
            untie refVar($index)
        } else {
            untie refVar
        }
    }
}

# link --
#
# Link an object to a variable of the same name.
# Unsetting the object variable only destroys the link.
# Destroying the object destroys the object variable.
#
# Syntax:
# link $objName
#
# Arguments:
# objName       Object to link

proc ::vutil::link {objName} {
    # Verify object
    if {![info object isa object $objName]} {
        return -code error "\"$objName\" is not an object"
    }
    # Clear up locks and links if $objName exists
    if {[info exists $objName]} {
        unlock $objName
        untie $objName
        unlink $objName
    }
    # Create traces on object variable and command
    trace add variable $objName read [list ::vutil::ReadLink $objName]
    trace add variable $objName write [list ::vutil::WriteLink $objName]
    trace add variable $objName unset [list ::vutil::UnsetLink $objName]
    trace add command $objName {rename delete} ::vutil::ObjectLink
    # Return the name of the object
    return $objName
}

# unlink --
#
# Unlink an object variable
#
# Syntax:
# unlink $objName ...
#
# Arguments:
# objName ...       Object to unlink

proc ::vutil::unlink {args} {
    foreach objName $args {
        if {![info object isa object $objName]} {
            return -code error "\"$objName\" is not an object"
        }
        if {![info exists $objName]} {
            return -code error "can't unlink \"$objName\": no such object"
        }
        trace remove variable $objName read [list ::vutil::ReadLink $objName]
        trace remove variable $objName write [list ::vutil::WriteLink $objName]
        trace remove variable $objName unset [list ::vutil::UnsetLink $objName]
        trace remove command $objName {rename delete} ::vutil::ObjectLink
    }
    return
}

# ReadLink --
# Set the object variable equal to the object value.

proc ::vutil::ReadLink {objName args} {
    set $objName [$objName]
}

# WriteLink --
# Set the object value equal to the object variable value.

proc ::vutil::WriteLink {objName args} {
    $objName = [set $objName]
}

# UnsetLink --
# Destroy the object

proc ::vutil::UnsetLink {objName args} {
    $objName destroy
}

# ObjectLink --
# Unset the object variable (which destroys the variable traces)

proc ::vutil::ObjectLink {objName newName args} {
    unset $objName; # Destroys variable and var traces (and command traces)
    if {$newName ne ""} {
        # Renaming to newName. Relink.
        link $newName
    }
}

# InitObj --
# Tracer to handle access error messages for object variables

proc ::vutil::InitObj {objName arrayName args} {
    upvar 1 $arrayName ""
    if {![info exists (value)]} {
        # If not initialized, throw DNE error.
        return -code error "can't read \"$objName\", no such variable"
    }
    trace remove variable (value) {read write} [list ::vutil::InitObj $objName]
    set (exists) 1
    return
}

# obj --
#
# Class for object variables that store a value and have garbage collection
#
# $obj                  # Get object value
# $obj info <$key>      # Get object info array (or single value)
# $obj = $value         # Value assignment
# $obj1 <- $obj2        # Object assignment (must be same class)
# $obj --> $varName     # Copy object (and set up tie/link)
#
# Arguments:
# varName       Variable to tie to the object
# value         Value to assign to the object
# name          Name of object

::oo::class create ::vutil::obj {
    variable ""; # Array of object data
    constructor {varName args} {
        # Check arity
        if {[llength $args] > 2} {
            ::errm::wrongNumArgs "obj new varName ??=? value | <- object?" \\
                    "obj create name varName ??=? value | <- object?"
        }
        # Initialize object
        set (type) [my Type]
        set (exists) 0; # Initialize
        # Set up initialization tracer
        trace add variable (value) {read write} [list ::vutil::InitObj [self]]
        # Interpret input
        if {[llength $args] == 1} {
            # obj new $varName $value
            my = [lindex $args 0]; # Assign value
        } elseif {[llength $args] == 2} {
            # obj new $varName = $value
            # obj new $varName <- $object
            lassign $args op value
            if {$op ni {= <-}} {
                ::errm::unknownOption $op {= <-}
            }
            my $op $value
        }
        # Link and tie object
        upvar 1 $varName refVar
        ::vutil::link [::vutil::tie refVar [self]]
        return
    }
    
    # Type --
    # Returns the type of object. Overwritten by "type add"
    method Type {} {}
    
    # info --
    #
    # Get meta data on object
    # Always has (exists) and (type), if (exists), has (value)
    #
    # Syntax:
    # $obj info <$key>
    #
    # Arguments:
    # obj       Object name
    # key       Optional key. Default "" returns all.
    
    method info {{key ""}} {
        if {$key eq ""} {
            return [lsort -stride 2 [array get ""]]
        } elseif {[info exists ($key)]} {
            return $($key)
        } else {
            ::errm::unknownOption $key [lsort [array names ""]]
        }
    }
    
    # GetValue (unknown) --
    #
    # Object value query (returns value).
    #
    # Syntax:
    # my GetValue
    # $obj
    
    method GetValue {} {
        return $(value)
    }
    method unknown {args} {
        if {[llength $args] == 0} {
            tailcall my GetValue
        }
        next {*}$args
    }
    unexport unknown
    
    # SetValue (=) --
    #
    # Value assignment (uses private method "SetValue"). 
    # Modify "SetValue" to add data validation and add metadata.
    # Returns object name
    #
    # Syntax:
    # my SetValue $value
    # $obj = $value
    #
    # Arguments:
    # obj       Object
    # value     Value to assign
    
    method SetValue {value} {
        set (value) $value
        return [self]
    }
    method = {args} {
        tailcall my SetValue {*}$args
    }
    export =
  
    # SetObject (<-) --
    # 
    # Right-to-left direct assignment (must be same class)
    #
    # Syntax:
    # my SetObject $obj
    # $obj1 <- $obj2
    #
    # Arguments:
    # obj1, obj2    Objects of same class

    method SetObject {objName} {
        if {![info object isa object $objName]} {
            return -code error "$objName is not an object"
        }
        if {![info object class $objName [info object class [self]]]} {
            return -code error "$objName not of same class as [self]"
        }
        # Set the object info array equal to the other one.
        array set "" [$objName info]
        return [self]
    }
    method <- {objName args} {
        tailcall my SetObject $objName {*}$args
    }
    export <-
    
    # CopyObject (-->) --
    #
    # Copy object to new variable
    #
    # Syntax:
    # my CopyObject $obj <$args ...>
    # $obj --> $varName <$args ...>
    #
    # Arguments:
    # obj           Object
    # varName       Variable to copy to
    # $args ...     Optional arguments to pass to ::oo::copy
    
    method CopyObject {varName args} {
        upvar 1 $varName refVar
        ::vutil::link [::vutil::tie refVar [::oo::copy [self] {*}$args]]
    }
    method --> {varName args} {
        tailcall my CopyObject $varName {*}$args
    }
    export -->
}

# type --
#
# Class that creates obj types

::oo::class create ::vutil::type {
    superclass ::oo::class
    constructor {type args} {
        # Rename class
        rename [self] ::vutil::type::$type
        oo::define [self] superclass ::vutil::obj
        
        next {*}$args
        [self class] add $type [self]
    }
}
::oo::objdefine ::vutil::type {
    variable typeClass
    method add {type class} {
        set typeClass($type) $class
        ::oo::define $class method Type {} [list return $type]
        ::oo::define $class variable ""
    }
    method remove {type} {
        if {[my exists $type]} {
            unset typeClass($type)
        }
    }
    method names {} {
        array names typeClass
    }
    method exists {type} {
        info exists typeClass($type)
    }
    method class {type} {
        if {![my exists $type]} {
            return -code error "type $type does not exist"
        }
        return $typeClass($type)
    }
    unexport create; # Only allow "new"
}

# new --
#
# Create a new object variable (with type)
#
# new $type $varName <"=" $value> <"<-" $object>

proc ::vutil::new {type varName args} {
    tailcall [type class $type] new $varName {*}$args
}

# BASIC OBJECT TYPES
################################################################################

# Define namespace for type classes
namespace eval ::vutil::type {}

# new obj --
#
# Blank object, no meta data.
::vutil::type add obj ::vutil::obj; # Add basic object type

# new string --
# length:   string length
# @:        string index

::vutil::type new string {
    method info {args} {
        set (length) [my length]
        next {*}$args
    }
    method length {} {
        string length $(value)
    }
    method @ {i} {
        string index $(value) $i
    }
    export @
}

# new list --
# length    list length
# @         list index/set

::vutil::type new list {
    method SetValue {value} {
        ::errm::assert $value is list
        next $value
    }
    method info {args} {
        set (length) [my length]
        next {*}$args
    }
    method length {} {
        llength $(value)
    }
    method @ {args} {
        if {[llength $args] >= 3 && [lindex $args end-1] eq "="} {
            # $list @ $i ?$i ...? = $value
            lset (value) {*}[lrange $args 0 end-2] [lindex $args end]
            return [self]
        } else {
            # $list @ ?$i ...?
            return [lindex $(value) {*}$args]
        }
    }
    export @
}

# new dict --
# size      dict size
# set       dict set
# get       dict get 

::vutil::type new dict {
    method SetValue {value} {
        if {[catch {dict size $value}]} {
            return -code error "expected dict value but got \"$value\""
        }
        next $value
    }
    method info {args} {
        set (size) [my size]
        next {*}$args
    }
    method size {} {
        dict size $(value)
    }
    method set {args} {
        dict set (value) {*}$args
        return [self]
    }
    method get {args} {
        dict get $(value) {*}$args
    }
}

# double (automatically uses expr)
::vutil::type new double {
    method SetValue {expr} {
        set value [::tcl::mathfunc::double [uplevel 1 [list expr $expr]]]
        next $value
    }
}

# int (automatically uses expr)
# +=        increment by a value
::vutil::type new int {
    method SetValue {expr} {
        set value [uplevel 1 [list expr $expr]]
        ::errm::assert $value is int
        next $value
    }
    # Add increment operators
    method += {incr} {
        incr (value) $incr
        return [self]
    }
    export +=
}

# Finally, provide the package
package provide vutil 0.3
