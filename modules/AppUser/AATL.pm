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
use AuthMethod::Database; # pull in the database auth module to avoid code duplication

## @method $ activate_user_byid($userid)
# Activate the user account with the specified id. This clears the user's
# activation code, and sets the activation timestamp.
#
# @param userid The ID of the user account to activate.
# @return true on success, undef on error.
sub activate_user_byid {
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


## @method $ activate_user($actcode)
# Activate the user account with the specified code. This clears the user's
# activation code, and sets the activation timestamp.
#
# @param actcode The activation code to look for and clear.
# @return A reference to the user's data on success, undef on error.
sub activate_user {
    my $self    = shift;
    my $actcode = shift;

    # Look up a user with the specified code
    my $userh = $self -> {"dbh"} -> prepare("SELECT * FROM ".$self -> {"settings"} -> {"database"} -> {"users"}."
                                             WHERE act_code = ?");
    $userh -> execute($actcode)
        or return $self -> self_error("Unable to perform user lookup: ". $self -> {"dbh"} -> errstr);

    my $user = $userh -> fetchrow_hashref()
        or return $self -> self_error("The specified activation code is not set for any users.");

    # Activate the user, and return their data if successful.
    return $self -> activate_user_byid($user -> {"user_id"}) ? $user : undef;
}


## @method @ create_user($username, $email)
# Create a new user, with a randomly generated password and activation code.
# This will set the user's name, email, password, activation code, and creation
# date, all other fields will be defaults.
#
# @param username The username of the user to create a record for.
# @param email    The email address of the new user.
# @return An array of two values: the first is either a reference to the user's
#         new record data on success, or undef on failure; the second is the
#         10 character alphanumeric unencrypted password to send to the user.
sub create_user {
    my $self     = shift;
    my $username = shift;
    my $email    = shift;

    # Generate some randomness for the authcode and password. These don't need
    # to be Insanely Secure, so this should be sufficient...
    my $actcode  = join("", map { ("a".."z", "A".."Z", 0..9)[rand 62] } 1..64);
    my $password = join("", map { ("a".."z", "A".."Z", 0..9)[rand 62] } 1..10);

    # Hash the password using the method AuthMethod::Database uses internally
    my $cryptpass = AuthMethod::Database::hash_password({"bcrypt_cost" => 14}, $password);

    # Do the insert
    my $userh = $self -> {"dbh"} -> prepare("INSERT INTO ".$self -> {"settings"} -> {"database"} -> {"users"}."
                                             (username, password, email, created, act_code)
                                             VALUES(?, ?, ?, UNIX_TIMESTAMP(), ?)");
    my $rows = $userh -> execute($username, $cryptpass, $email, $actcode);
    return $self -> self_error("Unable to perform user insert: ". $self -> {"dbh"} -> errstr) if(!$rows);
    return $self -> self_error("User insert failed, no rows added.") if($rows eq "0E0");

    # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
    #        Try to find a decent solution for this mess...
    my $userid = $self -> {"dbh"} -> {"mysql_insertid"};
    return $self -> self_error("Unable to obtain id for user '$username'") if(!$userid);

    my $user = $self -> get_user_byid($userid);

    return ($user, $password);
}


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
        if($self -> activate_user_byid($user -> {"user_id"})) {
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
