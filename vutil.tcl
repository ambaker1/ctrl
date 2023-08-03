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
    # Object reference name validation regex
    variable refNameExp {(::+|\w+)+(\(\w+\))?}
    # (::+|\w+)+            Matches alphanumeric namespace variables
    # (\(\w+\))?            Matches alphanumeric array indices
    # Exported Commands
    namespace export local; # Access local namespace variables (like global)
    namespace export default; # Set a variable if it does not exist
    namespace export lock unlock; # Hard set a Tcl variable
    namespace export tie untie $&; # Tie a Tcl variable to a Tcl object
    namespace export link unlink; # Create an object variable
    namespace export var type new; # Object variable class and types
    namespace export refsub; # Substitute object references
    namespace export leval lexpr; # List object evaluation
}

# VARIOUS VARIABLE UTILITIES
################################################################################

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

# READ-ONLY VARIABLES
################################################################################

# lock --
#
# Hard set of a variable. locked variables cannot be modified by set or default.
# Cannot lock an entire array.
#
# Syntax:
# lock $varName <$value>
#
# Arguments:
# varName       Variable to lock
# value         Value to set

proc ::vutil::lock {varName args} {
    upvar 1 $varName var
    if {[array exists var]} {
        return -code error "cannot lock an array"
    }
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
        WrongNumArgs "lock varName ?value?"
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
        if {[array exists var]} {
            return -code error "cannot unlock an array"
        }
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
# Prints warning to notify user that variable is locked
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
        puts stderr "failed to modify \"${varName}($index)\": read-only"
    } else {
        set var $value
        puts stderr "failed to modify \"$varName\": read-only"
    }
}

# TCLOO GARBAGE COLLECTION
################################################################################

# tie --
# 
# Tie a variable to a Tcl object, such that when the variable is modified or
# unset, by unset or by going out of scope, that the object is destroyed as well
# Overrides locks. 
# Reference name must match the refvar pattern
#
# Syntax:
# tie $refName <$object>
#
# Arguments:
# refName       Reference variable representing object
# objName       Name of Tcl object

proc ::vutil::tie {refName args} {
    # Create upvar link to reference variable
    ValidateRefName $refName
    if {$refName eq "&"} {
        upvar 1 ::$& refVar
    } else {
        upvar 1 $refName refVar
    }
    if {[array exists refVar]} {
        return -code error "cannot tie an array"
    }
    # Switch for arity (allow for self-tie)
    if {[llength $args] == 0} {
        if {[info exists refVar]} {
            set objName $refVar
        } else {
            return -code error "can't read \"$refName\": no such variable"
        }
    } elseif {[llength $args] == 1} {
        set objName [lindex $args 0]
    } else {
        WrongNumArgs "tie refName ?objName?"
    }
    # Verify object
    if {![info object isa object $objName]} {
        return -code error "\"$objName\" is not an object"
    }
    # Remove any existing lock trace and remove tie traces if not self-tying
    if {[info exists refVar]} {
        unlock refVar
        if {$objName eq $refVar} {
            untie refVar
        }
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
        if {[array exists refVar]} {
            return -code error "cannot untie an array"
        }
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
# Destroys associated Tcl object and removes traces
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
            trace remove variable refVar($index) {write unset} \
                    [list ::vutil::TieTrace $objName]
        } else {
            trace remove variable refVar {write unset} \
                    [list ::vutil::TieTrace $objName]
        }
    }
}

# ValidateRefName
#
# Returns error if not a valid reference name, blank otherwise.
#
# Syntax:
# ValidateRefName $refName
#
# Arguments:
# refName       Candidate reference name

proc ::vutil::ValidateRefName {refName} {
    if {![IsRefName $refName]} {
        return -code error "invalid object reference name \"$refName\""
    }
    return
}

# IsRefName --
#
# Returns true if valid refName, false otherwise.
#
# Syntax:
# IsRefName $refName
#
# Arguments:
# refName       Candidate reference name

proc ::vutil::IsRefName {refName} {
    variable refNameExp
    expr {$refName eq "&" || [regexp $refNameExp $refName]}
}

# $& --
#
# Access the global temporary object.
# The variable "$" syntax does not work with operators such as "&",
# so this is shorthand to call the last temporary object.
#
# Syntax:
# $& <$arg ...>
#
# Arguments:
# arg ...       Input arguments to temporary object.

proc ::vutil::$& {args} {
    tailcall [set ::$&] {*}$args
}

# gcoo --
#
# Superclass for objects with garbage collection. Not exported.
#
# Methods:
# -->       Copy object to new reference variable.

::oo::class create ::vutil::gcoo {
    # Constructor ties object to gc variable.
    constructor {refName} {
        uplevel 1 [list ::vutil::tie $refName [self]]
    }
    
    # CopyObject (-->) --
    #
    # Copy object to new variable (returns new object name)
    #
    # Syntax:
    # $obj --> $refName
    #
    # Arguments:
    # refName       Reference variable to copy to. "&" for temp object
    
    method CopyObject {refName} {
        uplevel 1 [list ::vutil::tie $refName [oo::copy [self]]]
    }
    method --> {refName} {
        tailcall my CopyObject $refName
    }
    export -->
}

# OBJECT VARIABLES
################################################################################

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

# OBJECT VARIABLE SUPERCLASS
################################################################################

# var --
#
# Subclass of gcoo, superclass for types. 
# Links the object using ::vutil::link, so that is 
# Note: Returns [self] for any method that modifies the object.
# Returns $value only for "unknown", and returns metadata with other methods.
# 
# Object creation:
# var new $refName <$value>
#
# Arguments:
# refName       Reference variable to tie to the object.
# value         Value to assign to the object variable.
# name          Name of object (for "create" method)
#
# Additional object methods:
# $varObj                   # Get object variable value
# $varObj print <arg ...>   # Print object variable value
# $varObj info <$field>     # Get object variable info array (or single value)
# $varObj = $value          # Value assignment
# $varObj := $expr          # Expression assignment
# $varObj1 <- $varObj2      # Object assignment (must be same class)

::oo::class create ::vutil::var {
    superclass ::vutil::gcoo
    variable ""; # Array of object data
    constructor {refName args} {
        # Check arity
        if {[llength $args] > 1} {
            WrongNumArgs "var new refName ?value?"
        }
        # Initialize object
        set (type) [my Type]
        set (exists) 0
        # Set up initialization tracer
        trace add variable (value) {read write} [list ::vutil::InitVar [self]]
        # Initialize if value input is provided
        if {[llength $args] == 1} {
            # var new $refName $value
            my = [lindex $args 0]; # Assign value
        }
        # Set up garbage collection
        next $refName
        # Set up object variable link
        ::vutil::link [self]
        return
    }
    
    # Modify <cloned> method for establishing initialization trace and
    # setting up object variable link. See documentation for oo::copy command
    method <cloned> {srcObj} {
        trace add variable (value) {read write} [list ::vutil::InitVar [self]]
        ::vutil::link [self]
        next $srcObj
    }
    
    # Type --
    #
    # Hard-coded variable type. Overwritten by "type new" or "type create"
    
    method Type {} {
        return var
    }
      
    # print --
    #
    # Print value of object (shorthand for puts)
    #
    # Syntax:
    # $varObj print <-nonewline> <$channelID>
    #
    # Arguments:
    # -nonewline        Print without newline
    # channelID         Channel ID open for writing. Default stdout (Tcl)
    
    method print {args} {
        puts {*}$args $(value)
    }

    # info --
    #
    # Get meta data on object
    # Always has (exists) and (type), and (value) if (exists) is true
    #
    # Syntax:
    # $varObj info <$field>
    #
    # Arguments:
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
    # Returns object name
    #
    # Syntax:
    # my SetValue $value
    # $varObj = $value
    # $varObj := $expr
    #
    # Arguments:
    # varObj    Variable object
    # value     Value to assign
    # expr      Value to pass through "expr" function
    
    method SetValue {value} {
        set (value) $value
        return [self]
    }
    method = {args} {
        tailcall my SetValue {*}$args
    }
    method := {expr} {
        my = [uplevel 1 [list expr $expr]]
    }
    export = :=
  
    # SetObject (<-) --
    # 
    # Right-to-left direct assignment (must be same class)
    # Right object must exist.
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
            return -code error "\"$objName\" is not an object"
        }
        if {![info object class $objName [info object class [self]]]} {
            return -code error "\"$objName\" not of same class as \"[self]\""
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
}

# InitVar --
# Tracer to handle access error messages for initialization of object variables

proc ::vutil::InitVar {objName arrayName args} {
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
    trace remove variable (value) {read write} [list ::vutil::InitVar $objName]
    set (exists) 1
    return
}

# Unexport the "create" class for "::vutil::var"
oo::objdefine ::vutil::var unexport create

# Initialize the $& global temp object
::vutil::var new & {}

# OBJECT VARIABLE TYPE FRAMEWORK
################################################################################

# type --
#
# Namespace ensemble for manipulating types.
# 
# Object creation:
# type new $type $arg ...
#
# Arguments:
# type          Name of type

namespace eval ::vutil::type {
    # Define variables
    variable typeClass
    set typeClass(var) ::vutil::var; # Initialize with basic "var" type
    # Define "type" ensemble
    namespace export new create; # Create a type class
    namespace export names exists; # Query type names
    namespace export class isa assert; # Query type classes
    namespace ensemble create
    # Make "type" available in this namespace
    namespace import ::vutil::type
}

# type new --
#
# Create a type class with an automatic name
#
# Syntax:
# type new $type $defScript
#
# Arguments:
# type          Name of type
# defScript     Class definition script  

proc ::vutil::type::new {type defScript} {
    tailcall type create $type ::vutil::type.$type $defScript
}

# type create --
#
# Create a type class with a specific name.
# Prefixes the defScript with type superclass, method, and variable.
#
# Syntax:
# type create $type $name $defScript
#
# Arguments:
# type          Name of type
# name          Name of class
# defScript     Class definition script  

proc ::vutil::type::create {type name defScript} {
    variable typeClass
    # Create class
    if {[type exists $type]} {
        return -code error "type \"$type\" already exists"
    }
    # Create the class (and get fully qualified name)
    set class [uplevel 1 [list ::oo::class create $name]]
    # Define the basics
    ::oo::define $class superclass [type class var]
    ::oo::define $class method Type {} [list return $type]
    ::oo::define $class variable ""
    # Call user-defined defScript.
    uplevel 1 [list ::oo::define $class $defScript]
    # Validate that defScript did not remove superclass definition
    if {$class ni [info class subclasses [type class var]]} {
        return -code error "class must be subclass of [type class var]"
    }
    # Unexport the "create" method
    ::oo::objdefine $class unexport create
    # Set up traces to remove the type if the class is destroyed.
    trace add command $class {rename delete} [list ::vutil::type::Tracer $type]
    # Register the type class now that the setup was successful
    set typeClass($type) $class
    # Return the class name, just like with oo::class create
    return $class
}

# Tracer --
#
# Command trace to re-register the type class if renamed, or to remove it if 
# the class is deleted.
#
# Syntax:
# Tracer $type $oldName $newName $op
# 
# Arguments:
# type          Name of type
# oldName       Fully qualified name of class before op
# newName       Fully qualified name of class after op
# op            "rename" or "delete". See Tcl documentation for "trace"

proc ::vutil::type::Tracer {type oldName newName op} {
    variable typeClass
    switch $op {
        rename {
            set typeClass($type) $newName
        }
        delete {
            unset typeClass($type)
        }
    }
}

# type names --
# 
# Get list of all defined types (unordered)
#
# Syntax:
# type names

proc ::vutil::type::names {} {
    variable typeClass
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
    
proc ::vutil::type::exists {type} {
    variable typeClass
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

proc ::vutil::type::class {type} {
    variable typeClass
    if {![type exists $type]} {
        return -code error "type \"$type\" does not exist"
    }
    return $typeClass($type)
}

# type isa --
#
# Check if an object is of a specific type (or a subtype)
#
# Syntax:
# type isa $type $object
#
# Arguments:
# type          Name of type
# object        Object name to check

proc ::vutil::type::isa {type object} {
    if {![info object isa object $object]} {
        return -code error "\"$object\" is not an object"
    }
    info object isa typeof $object [type class $type]
}

# type assert --
#
# Assert a type of an object variable
#
# Syntax:
# type assert $type $object
#
# Arguments:
# type          Name of type
# object        Object name to check

proc ::vutil::type::assert {type object} {
    if {![type isa $type $object]} {
        return -code error "assert type $type failed"
    }
}

# TYPE LIBRARY
################################################################################

# new --    
#
# Create a new object variable (with type)
# If reference name is "", it will create a temp object and return the value.
#
# new $type $refName $arg ...
#
# Arguments:
# type          Name of type
# refName       Reference variable name. "&" for temp object. "" for value.
# arg ...       Arguments for type class

proc ::vutil::new {type refName args} {
    # Value return
    if {$refName eq ""} {
        [type class $type] new & {*}$args
        return [$&]
    }
    # Object return
    tailcall [type class $type] new $refName {*}$args
}

# Note:
# This means that you can use the type library to validate Tcl types.
# set x [new float {} 5]
# puts $x; # 5.0
# $&; # 5.0; # Last temporary object

# new bool --
#
# Asserts boolean. Also has new if-statement control structure
#
# Additional methods:
# ?         Shorthand if-statement (tailcalls "if")

::vutil::type new bool {
    method SetValue {value} {
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
            ::vutil::WrongNumArgs "[self] ? body1 : body2"
        }
        set body2 [lindex $args 1]
        tailcall if $(value) $body1 else $body2
    }
    export ?
}

# new int --
#
# Asserts integer. Also has increment/decrement operators
#
# Additional methods:
# +=        Increment by value
# -=        Decrement by value
# ++        Increment by 1
# --        Decrement by 1

::vutil::type new int {
    method SetValue {value} {
        if {![string is integer -strict $value]} {
            return -code error "expected integer value but got \"$value\""
        }
        next $value
    }
    method += {expr} {
        incr (value) [uplevel 1 [list expr $expr]]
        return [self]
    }
    method -= {expr} {
        incr (value) [uplevel 1 [list expr -($expr)]]
        return [self]
    }
    method ++ {} {
        incr (value)
        return [self]
    }
    method -- {} {
        incr (value) -1
        return [self]
    }
    export += -= ++ --
}

# new float --
#
# Double-precision floating point value.
#
# Additional methods:
# +=        Add value
# -=        Subtract value
# *=        Multiply by value
# /=        Divide by value

::vutil::type new float {
    method SetValue {value} {
        next [::tcl::mathfunc::double $value]
    }
    method += {expr} {
        my := {$(value) + [uplevel 1 [list expr $expr]]}
    }
    method -= {expr} {
        my := {$(value) - [uplevel 1 [list expr $expr]]}
    }
    method *= {expr} {
        my := {$(value) * [uplevel 1 [list expr $expr]]}
    }
    method /= {expr} {
        my := {$(value) / [uplevel 1 [list expr $expr]]}
    }
    export := += -= *= /=
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
    
    # List expression
    method := {expr} {
        set (value) [uplevel 1 [list ::vutil::lexpr $expr]]
    }
    export :=
    
    # @ --
    #
    # Method to get or set a value in a list
    #
    # Syntax:
    # $list @ $i ?$i ...? = $value
    # $list @ $i ?$i ...? := $expr
    # $list @ ?$i ...?
    
    method @ {args} {
        switch [lindex $args end-1] {
            = { # $list @ $i ?$i ...? = $value
                set value [lindex $args end]
            }
            := { # $list @ $i ?$i ...? := $expr
                set value [uplevel 1 [list expr [lindex $args end]]]
            }
            default { # $list @ ?$i ...?
                return [lindex $(value) {*}$args]
            }
        }
        # Assign and return self
        lset (value) {*}[lrange $args 0 end-2] $value
        return [self]
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
    method print {args} {
        dict for {key value} $(value) {
            puts {*}$args [list $key $value]
        }
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
        return [self]
    }
    method unset {key args} {
        dict unset (value) $key {*}$args
        return [self]
    }
    method exists {key args} {
        dict exists $(value) $key {*}$args
    }
    method get {args} {
        dict get $(value) {*}$args
    }
}

# OBJECT ORIENTED EVALUATION
################################################################################

# refsub --
#
# Reference objects with the $@ symbol, like the $ symbol for variables.
# Returns the substituted body, and the list of reference names used.
# To refer to the global shared object, use $@&.
#
# To escape an object reference, use more @ symbols (such as $@@x)
# Examples:
# $@x: Refers to object value, replaced with ${$@(x)}
# $@@x: Escaped $@x
# $@@@x: Escaped $@@x (etc.)
#
# Syntax:
# refsub $body
#
# Arguments:
# body          Tcl body with object variable references with $@ref syntax

proc ::vutil::refsub {body} {
    variable refNameExp; # Regular expression for matching object variables
    # Initialize refMap with any & references
    set refMap ""
    if {[regsub -all {\$@&} $body {${$@(::$\&)}} body]} {
        dict set refMap ::$& ""
    }
    # Get all other references
    set refExp "\\\$@($refNameExp)"; # e.g. $@x(1)
    foreach {match refName ~ ~} [regexp -inline -all $refExp $body] {
        dict set refMap [string range $match 2 end] ""
    }
    # Perform regsub
    set body [regsub -all $refExp $body {${$@(\1)}}]
    # Handle recursion for escaped object references
    set body [string map {$@@ $@} $body]
    # Return updated body and list of substituted references
    return [list $body [dict keys $refMap]]
}

# leval --
# 
# Perform eval, but with list objects using @ref syntax
#
# Syntax:
# leval $body <"-->" refName>
#
# Arguments:
# body          Body to evaluate
# refName       Reference name to copy to. Default blank for value.

proc ::vutil::leval {body args} {
    # Interpret input
    set refName [GetRefName]
    if {[llength $args]} {
        WrongNumArgs "leval body ?--> refName?"
    }
    # Perform substitution and get names of substituted variables
    lassign [refsub $body] body subNames
    if {[llength $subNames] == 0} {
        return -code error "no list reference found"
    }
    # Get variable mapping
    set varMap ""
    foreach subName $subNames {
        upvar 1 $subName subVar
        if {![info exists subVar]} {
            return -code error "\"$subName\" does not exist"
        }
        if {[array exists subVar]} {
            return -code error "\"$subName\" is an array"
        }
        type assert list $subVar
        lappend varMap $@($subName) [$subVar]
    }
    # Perform lmap, and then unset the reference array
    set result [uplevel 1 [list lmap {*}$varMap $body]]
    upvar 1 $@ $@
    foreach subName $subNames {
        array unset $@ $subName
    }
    # Return a list
    tailcall new list $refName $result
}

# lexpr --
# 
# leval, but for math
#
# Syntax:
# lexpr $expr <"-->" refName>
#
# Arguments:
# expr          Expression, using $@refs for list references

proc ::vutil::lexpr {expr args} {
    # Interpret input
    set refName [GetRefName]
    if {[llength $args]} {
        WrongNumArgs "lexpr expr ?--> refName?"
    }
    # Return a list
    tailcall leval [list expr $expr] --> $refName
}

# GetRefName --
#
# Trims args of ?--> refName?. 
# Returns refName (blank if none).
#
# Syntax:
# set refName [GetRefName]
#
# Arguments:
# args:         Input arguments
# refName       Reference name

proc ::vutil::GetRefName {} {
    upvar 1 args args
    set refName ""; # Default
    if {[lindex $args end-1] eq "-->"} {
        # Get and validate reference name
        set refName [lindex $args end]
        if {$refName ne ""} {
            ValidateRefName $refName
        }
        # Trim args
        set args [lrange $args 0 end-2]
    }
    return $refName
}

# WrongNumArgs utility error message

proc ::vutil::WrongNumArgs {syntax} {
    return -level 2 -code error "wrong # args: should be \"$message\""
}

# Finally, provide the package
package provide vutil 0.12
