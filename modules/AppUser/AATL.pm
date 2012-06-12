## @file
# This file contains the AATL-specific user handling.
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

## @class
package AppUser::AATL;

use strict;
use base qw(AppUser);

## @method $ activate_user($userid)
# Activate the user account with the specified id. This clears the user's
# activation code, and sets the activation timestamp.
#
# @param userid The ID of the user account to activate.
# @return true on success, undef on error.
sub activate_user {
    my $self   = shift;
    my $userid = shift;

    my $activate = $self -> {"dbh"} -> prepare("UPDATE ".$self -> {"settings"} -> {"database"} -> {"users"}."
                                                SET activated = UNIX_TIMESTAMP(), act_code = NULL
                                                WHERE user_id = ?");
    my $rows = $activate -> execute($userid);
    return $self -> self_error("Unable to perform user update: ". $self -> {"dbh"} -> errstr) if(!$rows);
    return $self -> self_error("User update failed, no rows modified - bad userid?") if($rows eq "0E0");

    return 1;
}


## @method $ create_user(username, email)
#


## @method $ get_user_byemail($email, $onlyreal)
# Obtain the user record for the user with the specified email, if available.
# This returns a reference to a hash containing the user data corresponding
# to the user with the specified email, or undef if no users have the email
# specified.  If the onlyreal argument is set, the userid must correspond to
# 'real' user - bots or inactive users should not be returned.
#
# @param email    The email address to find an owner for.
# @param onlyreal If true, only users of type 0 or 3 are returned.
# @return A reference to a hash containing the user's data, or undef if the email
#         address can not be located (or is not real)
sub get_user_byemail {
    my $self     = shift;
    my $email    = shift;
    my $onlyreal = shift;

    return $self -> _get_user("email", $email, $onlyreal, 1);
}


## @method $ post_authenticate($username, $password, $auth)
# After the user has logged in, ensure that they have an in-system record.
# This is essentially a wrapper around the standard AppUser::post_authenticate()
# that handles things like user account activation checks.
#
# @param username The username of the user to perform post-auth tasks on.
# @param password The password the user authenticated with.
# @param auth     A reference to the auth object calling this.
# @return A reference to a hash containing the user's data on success,
#         undef otherwise. If this returns undef, an error message will be
#         appended to the specified auth's lasterr field.
sub post_authenticate {
    my $self     = shift;
    my $username = shift;
    my $password = shift;
    my $auth     = shift;

    # Let the superclass handle user creation
    my $user = $self -> SUPER::post_authenticate($username, $password, $auth);
    return undef unless($user);

    # User now exists, determine whether the user is active
    return $user if($user -> {"activated"});

    # User is inactive, does the account need activating?
    if(!$user -> {"act_code"}) {
        # No code provided, so just activate the account
        if($self -> activate_user($user -> {"user_id"})) {
            return $user;
        } else {
            $auth -> {"lasterr"} .= $self -> {"errstr"};
            return undef;
        }
    } else {
        $auth -> {"lasterr"} = "User account is not active.";
        return undef;
    }
}

1;
