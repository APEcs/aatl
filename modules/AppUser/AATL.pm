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

1;
