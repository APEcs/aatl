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
use News;

# ============================================================================
#  Permissions/Roles related.


# ============================================================================
#  Permissions/Roles related.

## @method $ used_capabilities()
# Generate a hash containing the capabilities this Feature tests user's roles
# against, and the description of the capabilities.
#
# @return A reference to a hash containing the capabilities this Feature uses
#         on success, undef on error.
sub used_capabilities {
    my $self = shift;

    return { "news.post"      => $self -> {"template"} -> replace_langvar("CAPABILITY_NEWS.POST"),
             "news.editown"   => $self -> {"template"} -> replace_langvar("CAPABILITY_NEWS.EDITOWN"),
             "news.editother" => $self -> {"template"} -> replace_langvar("CAPABILITY_NEWS.EDITOTHER"),
           };
}


# ============================================================================
#  News posts

## @method @ build_newpost_form()
# Determine whether the user has access to post new news entries, and if the
# user does generate the appropriate chunk of HTML.
#
# @return An array of two values: the html chunk to place in the new post form
#         area; and any content to add to the page header to load required js/css
sub build_newpost_form {
    my $self = shift;

    my $canpost = $self -> {"system"} ->


## @method @ build_news_list()
# Build a list of news posts the user can see. If the user has create or edit
# access, this will also insert the appropriate html to allow them to create
# posts or edit old ones.
#
# @return An array containing two values: the page content (the news posts),
#         and a string to place in the page header to load any required
#         javascript.
sub build_news_list {
    my $self = shift;

    return ("News!", "");
}


## @method $ page_display()
# Produce the string containing this block's full page content. This generates
# a course news page, including all navigation and decoration.
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;

    # Confirm that the user is logged in and has access to the course
    my $error = $self -> check_login_courseview(0);
    return $error if($error);

    # Generate the next list
    my ($content, $extrahead) = $self -> build_news_list();

    # User has access, generate the news page for the course.
    return $self -> generate_course_page("{L_FEATURE_NEWS_TITLE}", $content, $extrahead);
}

1;
