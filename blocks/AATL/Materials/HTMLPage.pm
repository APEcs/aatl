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
# along with this program.  If not, see http://www.gnu.org/licenses/.

## @class
# Allow the user to add a HTML page (popup, really) to the materials page.
#
package AATL::Materials::HTMLPage;

use strict;
use base qw(AATL::Materials);
use Webperl::Utils qw(is_defined_numeric);
use AATL::System::Materials::HTMLPage;

# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Overloaded constructor for Materials, loads the System::Materials model and other
# classes required to generate the forum pages.
#
# @param args A hash of values to initialise the object with. See the Block docs
#             for more information.
# @return A reference to a new AATL::Materials object on success, undef on error.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_)
        or return undef;

    # Create a news model to work through.
    $self -> {"htmlpage"} = AATL::System::Materials::HTMLPage -> new(dbh       => $self -> {"dbh"},
                                                                     settings  => $self -> {"settings"},
                                                                     logger    => $self -> {"logger"},
                                                                     module    => $self -> {"module"},
                                                                     roles     => $self -> {"system"} -> {"roles"},
                                                                     metadata  => $self -> {"system"} -> {"metadata"},
                                                                     courses   => $self -> {"system"} -> {"courses"},
                                                                     materials => $self -> {"materials"})
        or return SystemModule::set_error("HTMLPage initialisation failed: ".$System::Materials::errstr);

    # FIXME: This will probably need to instantiate the tags feature to get at AATL::Tags::block_display().
    # $self -> {"tags"} = $self -> {"modules"} -> load_module("AATL::Tags");

    return $self;
}


# ============================================================================
#  Controls/support

## @method private $ _build_section_controls($sectionid, $materialid, $userid, $metadataid)
# Generate the controls the user has access to for a material in a material section
# block.
#
# @param sectionid   The ID of the section the material is in.
# @param materialid  The ID of the material being displayed
# @param userid      The ID of the user viewing the material.
# @param metadataid  The ID of the material's metadata context.
# @return A string containing the material section block controls, if any.
sub _build_section_controls {
    my $self       = shift;
    my $sectionid  = shift;
    my $materialid = shift;
    my $userid     = shift;
    my $metadataid = shift;

    my $canedit = $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.htmlpage.edit") ? "enabled" : "disabled";
    my $candel  = $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.htmlpage.delete") ? "enabled" : "disabled";

    my $controls  = "";
    $controls .= $self -> {"template"} -> load_template("feature/materials/matcontrols/edit_${canedit}.tem",
                                                        {"***sid***"  => $sectionid,
                                                         "***mid***"  => $materialid,
                                                         "***type***" => $self -> {"typename"}});
    $controls .= $self -> {"template"} -> load_template("feature/materials/matcontrols/delete_${candel}.tem",
                                                        {"***sid***"  => $sectionid,
                                                         "***mid***"  => $materialid,
                                                         "***type***" => $self -> {"typename"}});

    return $self -> {"template"} -> load_template("feature/materials/matcontrols.tem", {"***controls***" => $controls }) if($controls);
    return "";
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


## @method private $ _build_api_view_response()
# Generate the HTML response to show in the material view popup window.
#
# @return A string containing the view data, or a reference to an error hash.
sub _build_api_view_response {
    my $self = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    my $materialid = is_defined_numeric($self -> {"cgi"}, "mid")
        or return $self -> api_errorhash("no_id", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_API_NOMID"));

    my $sectionid = is_defined_numeric($self -> {"cgi"}, "secid")
        or return $self -> api_errorhash("no_id", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_API_NOSID"));

    $self -> log("materials::htmlpage:view", "User viewing html page $materialid in section $sectionid");

    # View permission has already been checked by AATL::Materials::page_display() before calling this.
    # Get the material data...
    my $material = $self -> {"htmlpage"} -> get_view_data($self -> {"courseid"}, $sectionid, $materialid)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"htmlpage"} -> {"errstr"}}));

    return $self -> {"template"} -> load_template("feature/materials/htmlpage/view.tem",
                                                  {"***title***"    => $material -> {"title"},
                                                   "***htmlpage***" => $material -> {"htmldata"} });
}


# ============================================================================
#  Interface

## @method $ validate_material_fields($metadataid, $sectionid, $userid, $args)
# Validate any fields specific to this materials module, and store the validated
# results in the provided args hash.
#
# @param metadataid The ID of the metadata context associated with this material.
# @param sectionid  The ID of the section the material is in.
# @param userid     The ID of the user adding/editing the material.
# @param args       A reference to a hash to store field values in. Note that this will already
#                   contain at least two fields: 'title' and 'type'. If this is being invoked
#                   as part of an edit operation, args will also contain 'materialid', the id of
#                   the material being edited.
# @return An empty string if all fields validated correctly, otherwise a list of errors.
sub validate_material_fields {
    my $self       = shift;
    my $metadataid = shift;
    my $sectionid  = shift;
    my $userid     = shift;
    my $args       = shift;
    my ($error, $errors) = ("", "");

    my $op = "materials.htmlpage.".($args -> {"materialid"} ? "edit" : "add");
    if(!$self -> {"materials"} -> check_permission($metadataid, $userid, $op)) {
        $self -> log("error:materials::htmlpage:validate", "Permission denied when attempting material $op");
        $errors .= $self -> {"template"} -> load_template("error_item.tem", {"***error***" => $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_GENERAL_PERMS")});
    }

    ($args -> {"htmlpage"}, $error) = $self -> validate_htmlarea("htmlpage", {"required" => 1,
                                                                              "minlen"   => 8,
                                                                              "nicename" => $self -> {"template"} -> replace_langvar("MATERIALS_TYPE_HTMLPAGE"),
                                                                              "validate" => $self -> {"config"} -> {"Core:validate_htmlarea"}});
    $errors .= $self -> {"template"} -> load_template("error_item.tem", {"***error***" => $error}) if($error);

    return $errors
}


## @method $ add_material($sectionid, $materialid, $userid, $args)
# Add any material specific data to the database.
#
# @param sectionid  The ID of the section the material is being added to.
# @param materialid The ID of the material header allocated for the new material.
# @param userid     The ID of the user adding the material.
# @param args       A reference to a hash containing the complete material data.
# @return The new material data id on success, undef on error.
sub add_material {
    my $self       = shift;
    my $sectionid  = shift;
    my $materialid = shift;
    my $userid     = shift;
    my $args       = shift;

    return $self -> {"htmlpage"} -> add_material($materialid, $userid, $args -> {"htmlpage"});
}


## @method @ editform($materialid, $sectionid, $userid)
# Generate the HTML response to show in the material edit form popup window.
#
# @param sectionid  The ID of the section the material is in.
# @param materialid The ID of the material to edit.
# @param userid     The ID of the user editing the material.
# @return The name of the material, and a string containing the material edit form
#         on success, or a single reference to an API error hash on error.
sub editform {
    my $self       = shift;
    my $materialid = shift;
    my $sectionid  = shift;
    my $userid     = shift;

    $self -> log("materials::htmlpage:editform", "User editing html page $materialid in section $sectionid");

    my $editmaterial = $self -> {"materials"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                                $userid,
                                                                "materials.htmlpage.edit");
    if(!$editmaterial) {
        $self -> log("error:materials::htmlpage:editform", "Permission denied when attempting edit a html page");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIEDITMAT_PERMS"));
    }

    # Get the material data...
    my $material = $self -> {"htmlpage"} -> get_view_data($self -> {"courseid"}, $sectionid, $materialid)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"htmlpage"} -> {"errstr"}}));

    return ($material -> {"title"},
            $self -> {"template"} -> load_template("feature/materials/htmlpage/editform.tem",
                                                   {"***title***"    => $material -> {"title"},
                                                    "***htmlpage***" => $material -> {"htmldata"} }));
}


## @method $ edit_material($material, $userid, $args)
# Update the material-specific data in the database.
#
# @param material  A reference to a hash containing the material header.
# @param userid    The ID of the user adding the material.
# @param args      A reference to a hash containing the validated user-entered material data.
# @return The new material data id on success, undef on error
sub edit_material {
    my $self      = shift;
    my $material  = shift;
    my $userid    = shift;
    my $args      = shift;

    # For "editing", create a new material entry and link it to the existing on via a previous link...
    return $self -> {"htmlpage"} -> add_material($material -> {"id"}, $userid, $args -> {"htmlpage"}, $material -> {"type_data_id"});
}



## @method $ extra_header()
# Produce a string containing any javascript/css directives that need to be included in the
# page header.
#
# @return A string containing html to include in the page header
sub extra_header {
    my $self = shift;

    return $self -> {"template"} -> load_template("feature/materials/htmlpage/extraheader.tem");
}


## @method $ section_display($sectionid, $materialid, $userid)
# Produce the string containing this block's 'section fragment' if it has one. By default,
# this will return a string containing an error message. If section fragment content is
# needed, this must be overridden in the subclass.
#
# @param sectionid  The ID of the section containing the material to display.
# @param materialid The ID of the material to display.
# @param userid     The ID of the user viewing the section
# @return The string containing this block's section content fragment.
sub section_display {
    my $self       = shift;
    my $sectionid  = shift;
    my $materialid = shift;
    my $userid     = shift;

    my $material = $self -> {"htmlpage"} -> get_section_data($self -> {"courseid"}, $sectionid, $materialid)
        or return $self -> {"template"} -> load_template("feature/materials/section_error.tem", {"***message***" => $self -> {"htmlpage"} -> {"errmsg"}});

    my ($user, $mode);
    # Do the editor and creator match? If so there's no need for an 'edited' message
    if($material -> {"creator_id"} == $material -> {"editor_id"}) {
        $user = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byid($material -> {"creator_id"});
        $mode = $self -> {"template"} -> load_template("feature/materials/mode_added.tem",
                                                       {
                                                           "***time***" => $self -> {"template"} -> fancy_time($material -> {"created"})
                                                       });
    } else {
        $user = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byid($material -> {"editor_id"});
        $mode = $self -> {"template"} -> load_template("feature/materials/mode_added.tem",
                                                       {
                                                           "***time***" => $self -> {"template"} -> fancy_time($material -> {"edited"})
                                                       });
    }

    return $self -> {"template"} -> load_template("feature/materials/section_display.tem",
                                                  {"***type***"      => $self -> {"typename"},
                                                   "***title***"     => $material -> {"title"},
                                                   "***controls***"  => $self -> _build_section_controls($sectionid, $materialid, $userid, $material -> {"metadata_id"}),
                                                   "***size***"      => $self -> {"template"} -> humanise_bytes($material -> {"length"}),
                                                   "***addedit***"   => $mode,
                                                   "***profile***"   => $self -> build_url(block => "profile", pathinfo => [ $user -> {"username"} ]),
                                                   "***name***"      => $user -> {"fullname"},
                                                   "***gravhash***"  => $user -> {"gravatar_hash"},
                                                   "***extradata***" => "",
                                                   "***sid***"       => $sectionid,
                                                   "***mid***"       => $materialid,
                                                   "***type***"      => $self -> {"typename"},
                                                   "***maturl***"    => $self -> build_url(pathinfo => ["showmat",
                                                                                                        $self -> {"typename"},
                                                                                                        $sectionid,
                                                                                                        $materialid ]),
                                                  });
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
        } else {
            return $self->api_html_response($self -> api_errorhash('bad_op', $self -> {"template"} -> replace_langvar("API_BAD_OP")));
        }
    } else {
        die_log($self -> {"cgi"} -> remote_host(), "Attempt to directly access material module");
    }
}

1;
