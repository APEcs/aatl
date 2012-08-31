## @file
# This file contains the implementation of the AATL HTMLPage material model.
#
# @author  Chris Page &lt;chris@starforge.co.uk&gt;
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

## @class System::Materials::HTMLPage
# This class encapsulates operations involving HTMLPage Materials in the system.
package System::Materials::HTMLPage;

use strict;
use base qw(System::Materials);

# ==============================================================================
#  Creation/Cleanup

## @cmethod $ new(%args)
# Create a new HTMLPage object to manage HTMLPage creation and lookup.
# The minimum values you need to provide are:
#
# * dbh          - The database handle to use for queries.
# * settings     - The system settings object
# * logger       - The system logger object.
# * roles        - The system roles object.
# * courses      - The system courses object.
# * metadata     - The system metadata object.
#
# @param args A hash of key value pairs to initialise the object with.
# @return A new HTMLPage object, or undef if a problem occured.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_);
    return undef if(!$self);

    # Check that the required objects are present
    return SystemModule::set_error("No roles object available.")    if(!$self -> {"roles"});
    return SystemModule::set_error("No course object available.")   if(!$self -> {"courses"});
    return SystemModule::set_error("No metadata object available.") if(!$self -> {"metadata"});
    return SystemModule::set_error("No module object available.")   if(!$self -> {"module"});

    return $self;
}


# ============================================================================
#  Addition, etc...

## @method $ add_material($headerid, $userid, $pagedata, $previousid)
# Add a new entry to the HTMLPage table for this material.
#
# @param headerid   The ID of the material this is additional data for.
# @param userid     The ID of the user adding the page.
# @param pagedata   The HTML text itself.
# @param previousid The ID of a previous version of this page (undef = none)
# @return The new HTMLPage id on success, undef on error
sub add_material {
    my $self       = shift;
    my $headerid   = shift;
    my $userid     = shift;
    my $pagedata   = shift;
    my $previousid = shift;

    $self -> clear_error();


}

1;
