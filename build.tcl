package require tin 0.4
tin import tcltest
set vutil_version 0.1.1
set config ""
dict set config VERSION $vutil_version
tin bake src/vutil.tin build/vutil.tcl $config
tin bake src/pkgIndex.tin build/pkgIndex.tcl $config
tin bake src/install.tin build/install.tcl $config
tin bake doc/template/version.tin doc/template/version.tex $config

# Test vutil (this is a manual test)
source build/vutil.tcl
namespace import vutil::*


test default1 {
    The variable "a" does not exist. "default" sets it.
} -body {
    default a 5
} -result {5}

test default2 {
    The variable "a" now exists. "default" does nothing.
} -body { 
    default a 3
} -result {5}

test default3 {
    A "default" has no bearing on whether the "set" command works.
} -body {
    set a 3
} -result {3}

test lock1 {
    Lock will override a "set"
} -body {
    lock a 5
} -result {5}

test lock2 {
    "default" and "set" cannot override locks
} -body {
    set a 3
    default a 3
} -result {5}

test lock3 {
    Locks override locks
} -body {
    lock a 3
} -result {3}

test unlock {
    Unlocking allows for setting
} -body {
    unlock a
    set a 5
} -result {5}

# tie
test tie1 {
    Trying to tie to something that is not an object will return an error.
} -body {
    catch {tie a 5}
} -result {1}

# tie
# untie
test tie2 {
    Verify that you can tie and untie TclOO objects to variables
} -body {
    set result ""
    # Example from https://www.tcl.tk/man/tcl8.6/TclCmd/class.html
    oo::class create fruit {
        method eat {} {
            puts "yummy!"
        }
    }
    tie a [fruit new]
    set b $a; # Save alias
    lappend result [info object isa object $a]; # true
    lappend result [info object isa object $b]; # true
    unset a; # destroys object tied to $a
    lappend result [info exists a];             # false
    lappend result [info object isa object $b]; # false
    tie a [fruit new]
    untie a
    set b $a
    lappend result [info object isa object $a]; # true
    lappend result [info object isa object $b]; # true
    unset a
    lappend result [info exists a];             # false
    lappend result [info object isa object $b]; # true
    tie b $b; # Now b is tied
    $b destroy
    lappend result [info exists b]; # true, does not delete variable
    
} -result {1 1 0 0 1 1 0 1 1}

# Check number of failed tests
set nFailed $::tcltest::numTests(Failed)

# Clean up and report on tests
cleanupTests

# If tests failed, return error
if {$nFailed > 0} {
    error "$nFailed tests failed"
}

# Tests passed, copy build files to main folder and install
file copy -force {*}[glob -directory build *] [pwd]
source install.tcl; # Install vutil in main library