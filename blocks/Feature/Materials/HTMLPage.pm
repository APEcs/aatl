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
use System::Materials::HTMLPage;

# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Overloaded constructor for Materials, loads the System::Materials model and other
# classes required to generate the forum pages.
#
# @param args A hash of values to initialise the object with. See the Block docs
#             for more information.
# @return A reference to a new Feature::Materials object on success, undef on error.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_)
        or return undef;

    # Create a news model to work through.
    $self -> {"htmlpage"} = System::Materials::HTMLPage -> new(dbh       => $self -> {"dbh"},
                                                               settings  => $self -> {"settings"},
                                                               logger    => $self -> {"logger"},
                                                               module    => $self -> {"module"},
                                                               roles     => $self -> {"system"} -> {"roles"},
                                                               metadata  => $self -> {"system"} -> {"metadata"},
                                                               courses   => $self -> {"system"} -> {"courses"},
                                                               materials => $self -> {"materials"})
        or return SystemModule::set_error("HTMLPage initialisation failed: ".$System::Materials::errstr);

    # FIXME: This will probably need to instantiate the tags feature to get at Feature::Tags::block_display().
    # $self -> {"tags"} = $self -> {"modules"} -> load_module("Feature::Tags");

    return $self;
}


# ============================================================================
#  API

## @method private $ _build_api_addform_response()
# Generate the material addition form fragment for this module.
#
# @return A string containing the addition form, or a reference to an error hash.
sub _build_api_addform_response {
    my $self = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    $self -> log("materials::htmlpage:addform", "User attempting to add html page");

    my $addmaterial = $self -> {"materials"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                                $userid,
                                                                "materials.htmlpage.add");
    if(!$addmaterial) {
        $self -> log("error:materials::htmlpage:addform", "Permission denied when attempting add a new html page");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIADDMAT_PERMS"));
    }

    return $self -> {"template"} -> load_template("feature/materials/htmlpage/addform.tem");
}


# ============================================================================
#  Interface

## @method $ validate_material_fields($metadataid, $userid, $args, $errtem)
# Validate any fields specific to this materials module, and store the validated
# results in the provided args hash.
#
# @param args   A reference to a hash to store field values in. Note that this will already
#               contain at least two fields: 'title' and 'type'. If this is being invoked
#               as part of an edit operation, args will also contain 'materialid', the id of
#               the material being edited.
# @param errtem A string containing the error template to use when reporting errors. This
#               contains a replacement marker '***error***' that should be replaced with the
#               error message as needed.
# @return An empty string if all fields validated correctly, otherwise a list of errors.
sub validate_material_fields {
    my $self       = shift;
    my $metadataid = shift;
    my $userid     = shift;
    my $args       = shift;
    my $errtem     = shift;
    my ($error, $errors) = ("", "");

    my $op = "materials.htmlpage.".($args -> {"materialid"} ? "edit" : "add");
    if(!$self -> {"materials"} -> check_permission($metadataid, $userid, $op)) {
        $self -> log("error:materials::htmlpage:validate", "Permission denied when attempting material $op");
        $errors .= $self -> {"template"} -> process_template($errtem, {"***error***" => $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_GENERAL_PERMS")});
    }

    ($args -> {"message"}, $error) = $self -> validate_htmlarea("htmlpage", {"required" => 1,
                                                                             "minlen"   => 8,
                                                                             "nicename" => $self -> {"template"} -> replace_langvar("MATERIALS_TYPE_HTMLPAGE"),
                                                                             "validate" => $self -> {"config"} -> {"Core:validate_htmlarea"}});
    $errors .= $self -> {"template"} -> process_template($errtem, {"***error***" => $error}) if($error);

    return $errors
}


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
