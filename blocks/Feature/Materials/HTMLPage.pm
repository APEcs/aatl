## @file
# This file contains the implementation of the AATL HTML Page materials class
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

## @class Feature::Materials::HTMLPage
# Allow the user to add a HTML page (popup, really) to the materials page.
#
package Feature::Materials::HTMLPage;

use strict;
use base qw(Feature::Materials);
use Utils qw(is_defined_numeric);
use System::Materials;


# ============================================================================
#  API

## @method private $ _build_api_addform_response()
# Generate the material addition form fragment for this module.
#
# @return A string containing the addition form, or a reference to an error hash.
sub _build_api_addform_response {
    my $self = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    $self -> log("materials::htmlpage:addform", "User attempting to add htlm page");

    my $addmaterial = $self -> {"materials"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                                $userid,
                                                                "materials.addhtmlpage");
    if(!$addmaterial) {
        $self -> log("error:materials::htmlpage:addform", "Permission denied when attempting add a new section");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIADDMAT_PERMS"));
    }

    return $self -> {"template"} -> load_template("feature/materials/htmlpage/addform.tem");
}


# ============================================================================
#  Interface

## @method $ extra_header()
# Produce a string containing any javascript/css directives that need to be included in the
# page header.
#
# @return A strign containing html to include in the page header
sub extra_header {
    my $self = shift;

    return $self -> {"template"} -> load_template("feature/materials/extrahead.tem");
}


## @method $ section_display($section)
# Produce the string containing this block's 'section fragment' if it has one. By default,
# this will return a string containing an error message. If section fragment content is
# needed, this must be overridden in the subclass.
#
# @param section A reference to the base section data (subclasses may need to pull in additional
#                data)
# @return The string containing this block's section content fragment.
sub section_display {
    my $self    = shift;
    my $section = shift;

    return "<p class=\"error\">".$self -> {"template"} -> replace_langvar("BLOCK_SECTION_DISPLAY")."</p>";
}


## @method $ page_display()
# Produce the string containing this block's full page content. This generates
# a course news page, including all navigation and decoration.
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;

    # Is this an API call?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {
        if($apiop eq "addform") {
            return $self -> api_html_response($self -> _build_api_addform_response());
        } elsif($apiop eq "view") {
            return $self -> api_html_response($self -> _build_api_view_response());
        } elsif($apiop eq "edit") {

        } else {
            return $self->api_html_response($self -> api_errorhash('bad_op', $self -> {"template"} -> replace_langvar("API_BAD_OP")));
        }
    } else {
        die_log($self -> {"cgi"} -> remote_host(), "Attempt to directly access material module");
    }
}

1;
