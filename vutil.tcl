# vutil.tcl
################################################################################
# Utilities for working with variables in Tcl

# Copyright (C) 2023 Alex Baker, ambaker1@mtu.edu
# All rights reserved. 

# See the file "LICENSE" for information on usage, redistribution, and for a 
# DISCLAIMER OF ALL WARRANTIES.
################################################################################

# Define namespace
namespace eval ::vutil {
    # Exported Commands
    namespace export pvar; # Print variables and their values
    namespace export local; # Access local namespace variables (like global)
    namespace export default; # Set a variable if it does not exist
    namespace export lock unlock; # Hard set a Tcl variable
    namespace export tie untie; # Tie a Tcl variable to a Tcl object
    namespace export link unlink; # Create an object variable
    namespace export var type new; # Object variable class and types
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
        return -code error "wrong # args: want \"lock varName ?value?\""
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
        return -code error "wrong # args: want \"tie varName ?objName?\""
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
# objName ...       Object(s) to unlink

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
    # If not initialized, throw DNE error.
    if {![info exists (value)]} {
        return -code error "can't read \"$objName\", no such variable"
    }
    # If object value is initialized, but objvar is not, initialize objvar
    if {![info exists $objName]} {
        set $objName $(value)
    }
    # Remove variable traces and set "exists" array field
    trace remove variable (value) {read write} [list ::vutil::InitObj $objName]
    set (exists) 1
    return
}

# var --
#
# Class for object variables that store a value and have garbage collection
# 
# Object creation:
# var new $refName <arg ...> <<"="> $value> <"<-" $varObj>
# var create $name $refName <<"="> $value> <"<-" $varObj>
#
# Arguments:
# refName       Reference variable to tie to the object.
# value         Value to assign to the object variable ("=" keyword)
# var           Variable object to assign value from ("<-" option)
# name          Name of object (for "create" method)
#
# Object methods:
# $varObj                   # Get object variable value
# $varObj info <$field>     # Get object variable info array (or single value)
# $varObj = $value          # Value assignment
# $varObj1 <- $varObj2      # Object assignment (must be same class)
# $varObj --> $refName      # Copy object (and set up tie/link)

::oo::class create ::vutil::var {
    variable ""; # Array of object data
    constructor {refName args} {
        # Check arity
        if {[llength $args] > 2} {
            return -code error "wrong # args: want \"var new refName ??=?\
                    value | <- object?\" or \"var create name refName ??=?\
                    value | <- object?\""
        }
        # Initialize object
        set (type) [my Type]
        set (exists) 0
        # Set up initialization tracer
        trace add variable (value) {read write} [list ::vutil::InitObj [self]]
        # Interpret input
        if {[llength $args] == 1} {
            # var new $refName $value
            my = [lindex $args 0]; # Assign value
        } elseif {[llength $args] == 2} {
            # var new $refName = $value
            # var new $refName <- $object
            lassign $args op value
            if {$op ni {= <-}} {
                return -code error "unknown assignment operator \"$op\":\
                        want \"=\" or \"<-\""
            }
            my $op $value
        }
        # Tie and link object
        upvar 1 $refName refVar
        ::vutil::link [::vutil::tie refVar [self]]
        return
    }
    
    # Type --
    # Returns the type of object. Overwritten by "type add"
    method Type {} {return var}
    
    # info --
    #
    # Get meta data on object
    # Always has (exists) and (type), if (exists), has (value)
    #
    # Syntax:
    # $varObj info <$field>
    #
    # Arguments:
    # var       Object name
    # field     Optional field. Default "" returns all.
    
    method info {{field ""}} {
        if {$field eq ""} {
            return [lsort -stride 2 [array get ""]]
        } elseif {[info exists ($field)]} {
            return $($field)
        } else {
            return -code error "unknown info field \"$field\"" 
        }
    }
    
    # GetValue (unknown) --
    #
    # Object value query (returns value).
    #
    # Syntax:
    # my GetValue
    # $varObj
    
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
    # Returns object value
    #
    # Syntax:
    # my SetValue $value
    # $varObj = $value
    #
    # Arguments:
    # varObj    Variable object
    # value     Value to assign
    
    method SetValue {value} {
        set (value) $value
    }
    method = {args} {
        tailcall my SetValue {*}$args
    }
    export =
  
    # SetObject (<-) --
    # 
    # Right-to-left direct assignment (must be same class)
    # Returns object name
    #
    # Syntax:
    # my SetObject $varObj
    # $varObj1 <- $varObj2
    #
    # Arguments:
    # varObj1, varObj2      Variable objects of same class

    method SetObject {objName} {
        if {![info object isa object $objName]} {
            return -code error "$objName is not an object"
        }
        if {![info object class $objName [info object class [self]]]} {
            return -code error "$objName not of same class as [self]"
        }
        # Set the object info array equal to the other one.
        if {![$objName info exists]} {
            return -code error "can't read \"$objName\", no such variable"
        }
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
    # my CopyObject $refName <$args ...>
    # $varObj --> $refName <$args ...>
    #
    # Arguments:
    # varObj        Variable object
    # refName       Reference variable to copy to
    # $args ...     Optional arguments to pass to ::oo::copy
    
    method CopyObject {refName args} {
        upvar 1 $refName refVar
        ::vutil::link [::vutil::tie refVar [::oo::copy [self] {*}$args]]
    }
    method --> {refName args} {
        tailcall my CopyObject $refName {*}$args
    }
    export -->
}

# type --
#
# Metaclass that creates var types
# 
# Object creation:
# type new $type $arg ...
#
# Arguments:
# type          Name of type
# arg ...       Class definition arguments

::oo::class create ::vutil::type {
    superclass ::oo::class
    constructor {type args} {
        if {[[self class] exists $type]} {
            return -code error "type \"$type\" already exists"
        }
        rename [self] ::vutil::type.$type; # Rename class
        oo::define [self] superclass ::vutil::var
        next {*}$args
        [self class] add $type [self]
    }
}
::oo::objdefine ::vutil::type unexport create; # Only allow "new"

# Define "type" metaclass object methods
::oo::objdefine ::vutil::type {
    # Set up variable to store types and classes
    variable typeClass
    
    # type add --
    # 
    # Add a type directly
    #
    # Syntax:
    # type add $type $class
    #
    # Arguments:
    # type          Name of type
    # class         TclOO class name
    
    method add {type class} {
        set typeClass($type) $class
        ::oo::define $class method Type {} [list return $type]
        ::oo::define $class variable ""
    }
    
    # type remove --
    # 
    # Remove a type
    #
    # Syntax:
    # type remove $type
    #
    # Arguments:
    # type          Name of type
    
    method remove {type} {
        if {[my exists $type]} {
            unset typeClass($type)
        }
    }
        
    # type names --
    # 
    # Get list of all defined types
    #
    # Syntax:
    # type names

    method names {} {
        array names typeClass
    }
            
    # type exists --
    # 
    # Check whether a type exists or not
    #
    # Syntax:
    # type exists $type
    #
    # Arguments:
    # type          Name of type
    
    method exists {type} {
        info exists typeClass($type)
    }
    
    # type class --
    # 
    # Get class associated with type
    #
    # Syntax:
    # type class $type
    #
    # Arguments:
    # type          Name of type
    
    method class {type} {
        if {![my exists $type]} {
            return -code error "type $type does not exist"
        }
        return $typeClass($type)
    }
}; # end object definition

# new --    
#
# Create a new object variable (with type)
#
# new $type $varName <<"="> $value> <"<-" $object>

proc ::vutil::new {type varName args} {
    tailcall [type class $type] new $varName {*}$args
}

# BASIC DATA TYPES
################################################################################

# new var --
#
# Basic variable type (no meta data)

::vutil::type add var ::vutil::var

# new bool --
#
# Passes input through expr and asserts boolean
#
# Additional methods:
# ?         Shorthand if-statement (tailcalls "if")

::vutil::type new bool {
    method SetValue {expr} {
        set value [uplevel 1 [list expr $expr]]
        if {![string is boolean -strict $value]} {
            return -code error "expected boolean value but got \"$value\""
        }
        next $value
    }
    method ? {body1 args} {
        if {[llength $args] == 0} {
            tailcall if $(value) $body1
        } 
        if {[llength $args] != 2 || [lindex $args 0] ne {:}} {
            return -code error "wrong # args: want \"[self] ? body1 : body2\""
        }
        set body2 [lindex $args 1]
        tailcall if $(value) $body1 else $body2
    }
    export ?
}

# new int --
#
# Passes input through expr and asserts integer
#
# Additional methods:
# +=        Increment by value (pass through expr)
# -=        Decrement by value (pass through expr)
# ++        Increment by 1
# --        Decrement by 1

::vutil::type new int {
    method SetValue {expr} {
        set value [uplevel 1 [list expr $expr]]
        if {![string is integer -strict $value]} {
            return -code error "expected integer value but got \"$value\""
        }
        next $value
    }
    method += {expr} {
        incr (value) [uplevel 1 [list expr $expr]]
    }
    method -= {expr} {
        incr (value) [uplevel 1 [list expr -($expr)]]
    }
    method ++ {} {
        incr (value)
    }
    method -- {} {
        incr (value) -1
    }
    export += -= ++ --
}

# new float --
#
# Double-precision floating point value.
# Passes input through expr and mathfunc::double. 
#
# Additional methods:
# +=        Add value
# -=        Subtract value
# *=        Multiply by value
# /=        Divide by value

::vutil::type new float {
    method SetValue {expr} {
        set value [::tcl::mathfunc::double [uplevel 1 [list expr $expr]]]
        next $value
    }
    method += {expr} {
        set (value) [expr {$(value) + [uplevel 1 [list expr $expr]]}]
    }
    method -= {expr} {
        set (value) [expr {$(value) - [uplevel 1 [list expr $expr]]}]
    }
    method *= {expr} {
        set (value) [expr {$(value) * [uplevel 1 [list expr $expr]]}]
    }
    method /= {expr} {
        set (value) [expr {$(value) / [uplevel 1 [list expr $expr]]}]
    }
    export += -= *= /=
}

# new string --
#
# Everything is a string. This type adds the "length" and "@" methods.
# 
# Additional methods:
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
#
# Almost everything is a list. Asserts that input is a list.
# This data type also has "length" and "@" methods.
#
# Additional methods:
# length    list length (llength)
# @         list index/set (lindex/lset)

::vutil::type new list {
    method SetValue {value} {
        if {[catch {llength $value} result]} {
            return -code error $result
        }
        next $value
    }
    method info {args} {
        set (length) [my length]
        next {*}$args
    }
    method length {} {
        llength $(value)
    }
    
    # @ --
    #
    # Method to get or set a value in a list
    #
    # Syntax:
    # $list @ $i ?$i ...? = $value; # Returns object
    # $list @ ?$i ...?; # Returns value
    
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
#
# Tcl dictionary data type
#
# Additional methods:
# size      dict size
# set       dict set
# unset     dict unset
# get       dict get
# exists    dict exists

::vutil::type new dict {
    method SetValue {value} {
        if {[catch {dict size $value} result]} {
            return -code error $result
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
    method set {key args} {
        dict set (value) $key {*}$args
    }
    method unset {key args} {
        dict unset (value) $key {*}$args
    }
    method exists {key args} {
        dict exists $(value) $key {*}$args
    }
    method get {args} {
        dict get $(value) {*}$args
    }
}

# Finally, provide the package
package provide vutil 0.3
