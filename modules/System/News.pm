## @file
# This file contains the implementation of the AATL news post handling engine.
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

## @class System::News
# This class encapsulates operations involving news posts in the system.
package System::News;

use strict;
use base qw(SystemModule);

# ==============================================================================
#  Creation

## @cmethod $ new(%args)
# Create a new News object to manage news post creation and lookup.
# The minimum values you need to provide are:
#
# * dbh          - The database handle to use for queries.
# * settings     - The system settings object
# * metadata     - The system Metadata object.
# * roles        - The system Roles object.
# * logger       - The system logger object.
# * modules      - The system module/block loader object.
#
# @param args A hash of key value pairs to initialise the object with.
# @return A new News object, or undef if a problem occured.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_);
    return undef if(!$self);

    # Check that the required objects are present
    return SystemModule::set_error("No metadata object available.") if(!$self -> {"metadata"});
    return SystemModule::set_error("No roles object available.") if(!$self -> {"roles"});
    return SystemModule::set_error("No module loader object available.") if(!$self -> {"modules"});

    return $self;
}


# ============================================================================
#  Permissions layer

## @method $ check_permission($metadataid, $userid, $request, $rolelimit)
# Determine whether the user has the ability to perform the requested news action.
# This will check the user's capabilities in the metadata context supplied, and
# return true if the user is able to perform the requested action, false if they are not.
#
# @param metadataid The ID of the metadata context to check the user's permissions in. Should
#                   either be a news post context, or a course context.
# @param userid     The ID of the user to check permissions of.
# @param request    The requested capability, should generally be of the form `course.action`,
#                   if the request does not start with `course.`, it will be appended.
# @param rolelimit  An optional hash containing role ids as keys, and true or
#                   false as values. See Roles::user_has_capability() for more information.
# @return true if the user has the capability to perform the requested action, false if the
#         user does not, or undef on error.
sub check_permission {
    my $self       = shift;
    my $metadataid = shift;
    my $userid     = shift;
    my $request    = shift;
    my $rolelimit  = shift;

    # Fix up the request if needed
    $request = "news.$request" unless($request =~ /^news\./);

    # Determine whether the user has the capability
    return $self -> {"roles"} -> user_has_capability($metadataid, $userid, $request, $rolelimit);
}


1;
