## @file
# This file contains the implementation of the AATL news feature class.
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

## @class Feature::News
#
package Feature::News;

use strict;
use base qw(Feature);
use Data::Dumper;

## @method $ page_display()
# Produce the string containing this block's full page content. This generates
# a course news page, including all navigation and decoration.
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;

    print STDERR "In News block, checking login...\nSession:".Dumper($self -> {"session"});

    # Confirm that the user is logged in and has access to the course
    my $error = $self -> check_login_courseview(0);
    return $error if($error);

    # User has access, generate the news page for the course.
    print STDERR "User has access!";
}

1;
