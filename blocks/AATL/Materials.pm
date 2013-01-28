## @file
# This file contains the implementation of the AATL Materials feature class.
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
#
package AATL::Materials;

use strict;
use base qw(AATL);
use Webperl::Utils qw(is_defined_numeric);
use AATL::System::Materials;
use v5.12;

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
    $self -> {"system"} -> {"materials"} =
        $self -> {"materials"} = AATL::System::Materials -> new(dbh      => $self -> {"dbh"},
                                                                settings => $self -> {"settings"},
                                                                logger   => $self -> {"logger"},
                                                                module   => $self -> {"module"},
                                                                roles    => $self -> {"system"} -> {"roles"},
                                                                metadata => $self -> {"system"} -> {"metadata"},
                                                                courses  => $self -> {"system"} -> {"courses"})
        or return Webperl::SystemModule::set_error("Materials initialisation failed: ".$System::Materials::errstr);

    # FIXME: This will probably need to instantiate the tags feature to get at AATL::Tags::block_display().
    # $self -> {"tags"} = $self -> {"modules"} -> load_module("AATL::Tags");

    return $self;
}


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

    return { "materials.view"          => $self -> {"template"} -> replace_langvar("CAPABILITY_MATERIALS.VIEW"),
             "materials.viewhidden"    => $self -> {"template"} -> replace_langvar("CAPABILITY_MATERIALS.VIEWHIDDEN"),
             "materials.addsection"    => $self -> {"template"} -> replace_langvar("CAPABILITY_MATERIALS.ADDSECTION"),
             "materials.editsection"   => $self -> {"template"} -> replace_langvar("CAPABILITY_MATERIALS.EDITSECTION"),
             "materials.deletesection" => $self -> {"template"} -> replace_langvar("CAPABILITY_MATERIALS.DELSECTION"),
             "materials.addmaterials"  => $self -> {"template"} -> replace_langvar("CAPABILITY_MATERIALS.ADDMATERIALS"),
           };
}


# ============================================================================
#  Section handling/listing

## @method $ _build_section_admin($section, $userid, $permcache, $temcache)
# Build the block containing icons to trigger the operations the user has access
# to perform on the specified section.
#
# @param section   A reference to a hash containing the section data.
# @param userid    The ID of the user viewing the section.
# @param permcache A reference to a hash containing cached permissions.
# @param temcache  A reference to a hash containing cached templates.
# @return A string containing the section admin block HTML.
sub _build_section_admin {
    my $self      = shift;
    my $section   = shift;
    my $userid    = shift;
    my $permcache = shift;
    my $temcache  = shift;

    my $canedit   = $permcache -> {"editsection"} ? "enabled" : "disabled";
    my $candelete = $permcache -> {"deletesection"} ? "enabled" : "disabled";

    my $controls  = "";
       $controls .= $self -> {"template"} -> process_template($temcache -> {"sectionvis_".$canedit},
                                                              {"***id***"    => $section -> {"id"},
                                                               "***state***" => $section -> {"visible"} ? "set" : ""});
       $controls .= $self -> {"template"} -> process_template($temcache -> {"sectionopen_".$canedit},
                                                              {"***id***"    => $section -> {"id"},
                                                               "***state***" => $section -> {"open"} ? "set" : ""});
       $controls .= $self -> {"template"} -> process_template($temcache -> {"sectionedit_".$canedit},
                                                              {"***id***" => $section -> {"id"}});
       $controls .= $self -> {"template"} -> process_template($temcache -> {"sectiondel_".$candelete},
                                                              {"***id***" => $section -> {"id"}});

    return $self -> {"template"} -> process_template($temcache -> {"admincontrols"}, {"***controls***" => $controls });
}


## @method $ _build_section_controls($section, $userid, $permcache, $temcache)
# Build the block containing icons to trigger the operations the user has access
# to perform with the specified section (adding materials, etc).
#
# @param section   A reference to a hash containing the section data.
# @param userid    The ID of the user viewing the section.
# @param permcache A reference to a hash containing cached permissions.
# @param temcache  A reference to a hash containing cached templates.
# @return A string containing the section admin block HTML.
sub _build_section_controls {
    my $self      = shift;
    my $section   = shift;
    my $userid    = shift;
    my $permcache = shift;
    my $temcache  = shift;

    my $canadd   = $permcache -> {"addmaterials"} ? "enabled" : "disabled";

    my $controls  = "";
       $controls .= $self -> {"template"} -> process_template($temcache -> {"matsadd_".$canadd},
                                                              {"***id***" => $section -> {"id"}});

    return $self -> {"template"} -> process_template($temcache -> {"sectioncontrols"}, {"***controls***" => $controls }) if($controls);
    return "";
}


## @method private $ _build_section($section, $userid, $permcache, $temcache)
# Generate the HTML used to show a single section.
#
# @param section   A reference to a hash containing the section data.
# @param userid    The ID of the user viewing the section.
# @param permcache A reference to a hash containing cached permissions.
# @param temcache  A reference to a hash containing cached templates.
# @return A string containing the section HTML.
sub _build_section {
    my $self      = shift;
    my $section   = shift;
    my $userid    = shift;
    my $permcache = shift;
    my $temcache  = shift;

    # Build the section contents
    my $contents = "";
    my $matlist = $self -> {"materials"} -> get_section_materiallist($self -> {"courseid"}, $section -> {"id"}, $permcache -> {"viewhidden"})
        or $self -> {"logger"} -> die_log($self -> {"cgi"} -> remote_host(), "Fatal error: ".$self -> {"materials"} -> {"errstr"});

    foreach my $material (@{$matlist}) {
        # Caching done in System::Materials makes this safe enough to do...
        my $matmodule = $self -> {"matmodules"} -> {$material -> {"module_name"}} =
            $self -> {"materials"} -> load_materials_module($material -> {"module_name"})
            or $self -> {"logger"} -> die_log($self -> {"cgi"} -> remote_host(), "Unsupported material module '"..$material -> {"module_name"}."'");

        $contents .= $matmodule -> section_display($section -> {"id"}, $material -> {"id"}, $userid, $permcache -> {"sortlist"});
    }

    # Section admin bar and controls
    my $admin = $self -> _build_section_admin($section, $userid, $permcache, $temcache);
    my $controls = $self -> _build_section_controls($section, $userid, $permcache, $temcache);

    # Work out the classes to apply to the section
    my $section_class = "";
    $section_class .= " sec-hide" unless($section -> {"visible"});
    $section_class .= " sec-close" unless($section -> {"open"});

    # state for the open/closed toggle
    my $state = $section -> {"open"} ? "open" : "closed";

    return $self -> {"template"} -> process_template($temcache -> {"section"},
                                                     {"***id***"       => $section -> {"id"},
                                                      "***class***"    => $section_class,
                                                      "***admin***"    => $admin,
                                                      "***state***"    => $state,
                                                      "***title***"    => $section -> {"title"},
                                                      "***content***"  => $contents,
                                                      "***controls***" => $controls,
                                                      "***sortable***" => $permcache -> {"sortlist"} ? " sortable" : "",
                                                     });
}


## @method private @ _build_section_list($error)
# Generate the HTML to show in the page body containing the section list.
#
# @param error An optional error message to show at the top of the page; this
#              will be wrapped in an error box for you.
# @return An array of two values: a string containing the page content, and a
#         string with extra header directives.
sub _build_section_list {
    my $self = shift;
    my $error = shift;

    # Wrap the error message in a message box if we have one.
    $error = $self -> {"template"} -> load_template("feature/materials/error_box.tem", {"***message***" => $error})
        if($error);

    my $userid = $self -> {"session"} -> get_session_userid();

    # Can the user view hidden sections?
    my $metadataid = $self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"});

    # Cache some templates for list generation
    my $temcache = { "section"              => $self -> {"template"} -> load_template("feature/materials/section.tem"),
                     "admincontrols"        => $self -> {"template"} -> load_template("feature/materials/admincontrols.tem"),
                     "sectionedit_enabled"  => $self -> {"template"} -> load_template("feature/materials/controls/section_edit_enabled.tem"),
                     "sectionedit_disabled" => $self -> {"template"} -> load_template("feature/materials/controls/section_edit_disabled.tem"),
                     "sectiondel_enabled"   => $self -> {"template"} -> load_template("feature/materials/controls/section_delete_enabled.tem"),
                     "sectiondel_disabled"  => $self -> {"template"} -> load_template("feature/materials/controls/section_delete_disabled.tem"),
                     "sectionvis_enabled"   => $self -> {"template"} -> load_template("feature/materials/controls/default_visible_enabled.tem"),
                     "sectionvis_disabled"  => $self -> {"template"} -> load_template("feature/materials/controls/default_visible_disabled.tem"),
                     "sectionopen_enabled"  => $self -> {"template"} -> load_template("feature/materials/controls/default_opened_enabled.tem"),
                     "sectionopen_disabled" => $self -> {"template"} -> load_template("feature/materials/controls/default_opened_disabled.tem"),
                     "sectioncontrols"      => $self -> {"template"} -> load_template("feature/materials/sectioncontrols.tem"),
                     "matsadd_enabled"      => $self -> {"template"} -> load_template("feature/materials/controls/material_add_enabled.tem"),
                     "matsadd_disabled"     => $self -> {"template"} -> load_template("feature/materials/controls/material_add_disabled.tem"),
    };

    # And some permissions
    my $permcache = {
        "viewhidden"    => $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.viewhidden"),
        "addsection"    => $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.addsection"),
        "editsection"   => $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.editsection"),
        "deletesection" => $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.deletesection"),
        "sortlist"      => $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.sortlist"),
        "addmaterials"  => $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.addmaterials"),
    };
    my $sortlist   = $permcache -> {"sortlist"} ? "enabled" : "disabled";
    my $addsection = $permcache -> {"addsection"} ? "enabled" : "disabled";

    my $sections = $self -> {"materials"} -> get_section_list($self -> {"courseid"}, $permcache -> {"viewhidden"})
        or $self -> {"logger"} -> die_log($self -> {"cgi"} -> remote_host(), "Fatal error: ".$self -> {"materials"} -> {"errstr"});

    my $sectionlist = "";
    foreach my $section (@{$sections}) {
        $sectionlist .= $self -> _build_section($section, $userid, $permcache, $temcache);
    }

    return ($self -> {"template"} -> load_template("feature/materials/sectionlist.tem",
                                                   {"***error***"    => $error,
                                                    "***entries***"  => $sectionlist,
                                                    "***addopt***"   => $self -> {"template"} -> load_template("feature/materials/addsection_${addsection}.tem"),
                                                    "***listsort***" => $self -> {"template"} -> load_template("feature/materials/listsort_${sortlist}.tem")
                                                   }),
            $self -> extra_header());
}


# ============================================================================
#  Validation support functions

## @method private @ _validate_material_fields($metadataid, $userid, $materialid)
# Determine whether the materials information submitted by the user is valid.
# This will validate any common material fields, and then invoke the appropriate
# materials module to validate the remaining fields.
#
# @param metadataid The ID of the metadata context the material is in.
# @param userid     The ID of the user adding or editing the material.
# @param materialid If this function is being called as part of an edit process,
#                   this parameter contains the ID of the material being edited.
# @return An array of three values: a reference to a hash containing the validated
#         arguments, a reference to the materials module used to validate the
#         material-specific fields, and a string containing a list of errors, if
#         any were encountered.
sub _validate_material_fields {
    my $self                    = shift;
    my $metadataid              = shift;
    my $userid                  = shift;
    my ($args, $error, $errors) = ({"materialid" => shift}, "", "");

    my $errtem = $self -> {"template"} -> load_template("error_item.tem");

    # Title and type need validating properly...
    ($args -> {"title"}, $error) = $self -> validate_string("title", {"required" => 1,
                                                                      "nicename" => $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_NEWMAT_TITLE"),
                                                                      "minlen"   => 8,
                                                                      "maxlen"   => 128});
    $errors .= $self -> {"template"} -> process_template($errtem, {"***error***" => $error}) if($error);

    ($args -> {"type"}, $error) = $self -> validate_options("type", {"required" => 1,
                                                                     "nicename" => $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_NEWMAT_TYPE"),
                                                                     "source"   => $self -> {"settings"} -> {"database"} -> {"feature::material_modules"},
                                                                     "where"    => "WHERE id > 0 AND module_name = ?"});
    $errors .= $self -> {"template"} -> process_template($errtem, {"***error***" => $error}) if($error);

    # If the type is bad, nothing else can be done.
    return ($args, undef, $errors) if($error);

    # convert the type to a typeid
    $args -> {"typeid"} = $self -> {"materials"} -> get_material_typeid($args -> {"type"})
        or $errors .= $self -> {"template"} -> process_template($errtem, {"***error***" => $self -> {"materials"} -> {"errstr"}});

    # Load the material module, so that it can handle validating its own fields
    my $module = $self -> {"materials"} -> load_materials_module($args -> {"type"});

    # This should never actually happen - the validation on type should detect bad types - but check anyway
    $errors .= $self -> {"template"} -> process_template($errtem, {"***error***"  => $self -> {"materials"} -> {"errstr"},
                                                                   "***module***" => $args -> {"type"}})
        if(!$module);

    # Now get the material module to do its thing
    $errors .= $module -> validate_material_fields($metadataid, $userid, $args, $errtem)
        if($module);

    return ($args, $module, $errors);
}


# ============================================================================
#  API functions

## @method private $ _build_api_addsection_response()
# Determine whether the user is allowed to add sections, and if they are try to
# add a new one to the current course.
#
# @return A string or hash containing the API response.
sub _build_api_addsection_response {
    my $self   = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    $self -> log("materials:addsection", "User attempting to add material section");

    my $addsection = $self -> {"materials"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                                $userid,
                                                                "materials.addsection");
    if(!$addsection) {
        $self -> log("error:materials:addsection", "Permission denied when attempting add a new section");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIADDSEC_PERMS"));
    }

    my $sectionid = $self -> {"materials"} -> add_section($self -> {"courseid"}, $userid, $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_DEFAULT_TITLE"))
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    $self -> log("materials:addsection", "User added new section with id $sectionid");

    my $section = $self -> {"materials"} -> get_section($sectionid)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    # Cache some templates for list generation
    my $temcache = { "section"              => $self -> {"template"} -> load_template("feature/materials/section.tem"),
                     "admincontrols"        => $self -> {"template"} -> load_template("feature/materials/admincontrols.tem"),
                     "sectionedit_enabled"  => $self -> {"template"} -> load_template("feature/materials/controls/section_edit_enabled.tem"),
                     "sectionedit_disabled" => $self -> {"template"} -> load_template("feature/materials/controls/section_edit_disabled.tem"),
                     "sectiondel_enabled"   => $self -> {"template"} -> load_template("feature/materials/controls/section_delete_enabled.tem"),
                     "sectiondel_disabled"  => $self -> {"template"} -> load_template("feature/materials/controls/section_delete_disabled.tem"),
                     "sectionvis_enabled"   => $self -> {"template"} -> load_template("feature/materials/controls/default_visible_enabled.tem"),
                     "sectionvis_disabled"  => $self -> {"template"} -> load_template("feature/materials/controls/default_visible_disabled.tem"),
                     "sectionopen_enabled"  => $self -> {"template"} -> load_template("feature/materials/controls/default_opened_enabled.tem"),
                     "sectionopen_disabled" => $self -> {"template"} -> load_template("feature/materials/controls/default_opened_disabled.tem"),
                     "sectioncontrols"      => $self -> {"template"} -> load_template("feature/materials/sectioncontrols.tem"),
                     "matsadd_enabled"      => $self -> {"template"} -> load_template("feature/materials/controls/material_add_enabled.tem"),
                     "matsadd_disabled"     => $self -> {"template"} -> load_template("feature/materials/controls/material_add_disabled.tem"),
    };

    # And some permissions
    my $metadataid = $self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"});
    my $permcache = {
        "viewhidden"    => $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.viewhidden"),
        "addsection"    => $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.addsection"),
        "editsection"   => $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.editsection"),
        "deletesection" => $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.deletesection"),
        "sortlist"      => $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.sortlist"),
        "addmaterials"  => $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.addmaterials"),
    };

    return $self -> _build_section($section, $userid, $permcache, $temcache);
}


## @method $ _build_api_sectionorder_response()
# Reorder the sections in the materials page for the current course, if permitted.
#
# @return A reference to a hash containing the API response.
sub _build_api_sectionorder_response {
    my $self = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    # Check that the user even has permission to sort.
    $self -> log("materials:sectionorder", "User attempting to reorder sections");

    my $metadataid = $self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"});
    if(!$self -> {"materials"} -> check_permission($metadataid, $userid, "materials.sortlist")) {
        $self -> log("error:materials:sectionorder", "Permission denied when attempting to reorder section");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APISORTSEC_PERMS"));
    }
    my $viewhidden = $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.viewhidden");

    # fetch the list of sections, that they may be iterated over
    my $sections = $self -> {"materials"} -> get_section_list($self -> {"courseid"}, $viewhidden);
    foreach my $section (@{$sections}) {
        my $pos = is_defined_numeric($self -> {"cgi"}, "section-".$section -> {"id"});

        if(defined($pos)) {
#            $self -> log("materials:sectionorder", "Set section ".$section -> {"id"}." to position $pos");
            $self -> {"materials"} -> set_section_order($self -> {"courseid"}, $section -> {"id"}, $pos)
                or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}))
        } else {
            $self -> log("error:materials:sectionorder", "No position set for section ".$section -> {"id"});
        }
    }
    $self -> log("materials:sectionorder", "Section reorder complete");

    return { "response" => {"sort" => "ok"} };
}


## @method private $ _build_api_delsection_response()
# Determine whether the user is allowed to delete sections, and if they are try to
# delete the section specified by the user.
#
# @return A string or hash containing the API response.
sub _build_api_delsection_response {
    my $self   = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    my $id = $self -> {"cgi"} -> param("secid")
        or return $self -> api_errorhash("no_secid", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIDELSEC_NOID"));

    $self -> log("materials:delsection", "User attempting to delete material section $id");

    my $delsection = $self -> {"materials"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                                $userid,
                                                                "materials.deletesection");
    if(!$delsection) {
        $self -> log("error:materials:delsection", "Permission denied when attempting delete section $id");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIDELSEC_PERMS"));
    }

    $self -> {"materials"} -> delete_section($self -> {"courseid"}, $id, $userid)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    $self -> log("materials:delsection", "Section delete complete");

    return { "response" => {"delete" => "ok"} };
}


## @method private $ _build_api_editsection_response()
# Determine whether the user is allowed to edit section titless, and if they are try to
# update the title for the section specified by the user.
#
# @return A string or hash containing the API response.
sub _build_api_editsection_response {
    my $self   = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    my $id = $self -> {"cgi"} -> param("secid")
        or return $self -> api_errorhash("no_secid", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIDELSEC_NOID"));

    $self -> log("materials:editsection", "User attempting to edit material section $id");

    my $editsection = $self -> {"materials"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                                $userid,
                                                                "materials.editsection");
    if(!$editsection) {
        $self -> log("error:materials:editsection", "Permission denied when attempting edit section $id");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIEDITSEC_PERMS"));
    }

    my ($title, $error) = $self -> validate_string("title", {"required" => 1,
                                                             "nicename" => $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIEDITSEC_TITLE"),
                                                             "minlen"   => 8,
                                                             "maxlen"   => 128});
    return $self -> api_errorhash("bad_title", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIEDITSEC_BADT",
                                                                                        {"***error***" => $error}))
        if($error);

    $self -> {"materials"} -> edit_section($self -> {"courseid"}, $id, $title)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    $self -> log("materials:editsection", "Section updated with title '$title'");

    return { "response" => {"title" => $title} };
}


## @method private $ _build_api_defaultvisible_response()
# Determine whether the user is allowed to edit sections, and if they are try to
# update the default visibility for the specified section.
#
# @return A string or hash containing the API response.
sub _build_api_defaultvisible_response {
    my $self   = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    my $id = $self -> {"cgi"} -> param("secid")
        or return $self -> api_errorhash("no_secid", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIDELSEC_NOID"));

    $self -> log("materials:defvis_section", "User attempting to edit visibility of material section $id");

    my $editsection = $self -> {"materials"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                                $userid,
                                                                "materials.editsection");
    if(!$editsection) {
        $self -> log("error:materials:defvis_section", "Permission denied when attempting edit section $id");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIVISSEC_PERMS"));
    }

    my $section = $self -> {"materials"} -> get_section($id)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIVISSEC_BADCID"))
        if($section -> {"course_id"} != $self -> {"courseid"});

    my $visible = !$section -> {"visible"};
    $self -> {"materials"} -> set_section_visible($self -> {"courseid"}, $id, $visible)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    $self -> log("materials:defvis_section", "Section $id updated with visibility $visible");

    return { "visible" => {"set" => $visible} };
}


## @method private $ _build_api_defaultopen_response()
# Determine whether the user is allowed to edit sections, and if they are try to
# update the default open state for the specified section.
#
# @return A string or hash containing the API response.
sub _build_api_defaultopen_response {
    my $self   = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    my $id = $self -> {"cgi"} -> param("secid")
        or return $self -> api_errorhash("no_secid", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIDELSEC_NOID"));

    $self -> log("materials:defopen_section", "User attempting to edit visibility of material section $id");

    my $editsection = $self -> {"materials"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                                $userid,
                                                                "materials.editsection");
    if(!$editsection) {
        $self -> log("error:materials:defopen_section", "Permission denied when attempting edit section $id");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIVISSEC_PERMS"));
    }

    my $section = $self -> {"materials"} -> get_section($id)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIVISSEC_BADCID"))
        if($section -> {"course_id"} != $self -> {"courseid"});

    my $open = !$section -> {"open"};
    $self -> {"materials"} -> set_section_opened($self -> {"courseid"}, $id, $open)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    $self -> log("materials:defopen_section", "Section $id updated with open status $open");

    return { "open" => {"set" => $open } };
}


## @method private $ _build_api_addmatform_response()
# Generate the material addition form to send back to the client to embed in the
# page.
#
# @return A string or hash containing the API response.
sub _build_api_addmatform_response {
    my $self = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    my $id = $self -> {"cgi"} -> param("secid")
        or return $self -> api_errorhash("no_secid", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIDELSEC_NOID"));

    $self -> log("materials:addform", "User attempting to add material to section $id");

    my $addmaterial = $self -> {"materials"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                                 $userid,
                                                                 "materials.addmaterials");
    if(!$addmaterial) {
        $self -> log("error:materials:addform", "Permission denied when attempting add a new material");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIADDMAT_PERMS"));
    }

    my $modules = $self -> {"materials"} -> get_module_optionlist()
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    return $self -> {"template"} -> load_template("feature/materials/addform.tem", {"***id***"      => $id,
                                                                                    "***modules***" => $self -> {"template"} -> build_optionlist($modules)});
}


## @method private $ _build_api_addmat_response()
# Add a material to the appropriate section in the current course. This adds a material
# header, and calls the appropriate materials module to add the material-specific data
# to the database.
#
# @return A string or hash containing the API response.
sub _build_api_addmat_response {
    my $self = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    my $sectionid = $self -> {"cgi"} -> param("secid")
        or return $self -> api_errorhash("no_secid", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIDELSEC_NOID"));

    $self -> log("materials:addmat", "User attempting to add material to section $sectionid");

    my $metadataid = $self -> {"materials"} -> get_section_metadataid($self -> {"courseid"}, $sectionid);
    my $addmaterial = $self -> {"materials"} -> check_permission($metadataid,
                                                                 $userid,
                                                                 "materials.addmaterials");
    if(!$addmaterial) {
        $self -> log("error:materials:addmat", "Permission denied when attempting add a new material");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIADDMAT_PERMS"));
    }

    my ($args, $module, $errors) = $self -> _validate_material_fields($metadataid, $userid);
    return $self -> api_errorhash("bad_values", $self -> {"template"} -> load_template("error_list.tem",
                                                                                       {"***message***" => "{L_FEATURE_MATERIALS_APIADD_FAIL}",
                                                                                        "***errors***"  => $errors}))
        if($errors);

    my $materialid = $self -> {"materials"} -> add_material($self -> {"courseid"}, $sectionid, $userid, $args -> {"typeid"}, $args -> {"title"})
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    my $dataid = $module -> add_material($sectionid, $materialid, $userid, $args)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $module -> {"errstr"}}));

    $self -> {"materials"} -> set_material_dataid($self -> {"courseid"}, $sectionid, $materialid, $dataid)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    $self -> log("materials:addmat", "User add material with title '".$args -> {"title"}."' to section $sectionid");

    return $module -> section_display($sectionid, $materialid, $userid);
}


## @method private $ _build_api_deletemat_response()
# Delete a material from the system. This actually just marks the material as deleted,
# rather than actually deleting it.
#
# @return A string or hash containing the API response.
sub _build_api_deletemat_response {
    my $self   = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    my $materialid = is_defined_numeric($self -> {"cgi"}, "mid")
        or return $self -> api_errorhash("no_id", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_API_NOMID"));

    my $sectionid = is_defined_numeric($self -> {"cgi"}, "secid")
        or return $self -> api_errorhash("no_id", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_API_NOSID"));

    $self -> log("materials:delmat", "User attempting delete of $materialid in section $sectionid");

    my $material = $self -> {"materials"} -> get_material($self -> {"courseid"}, $sectionid, $materialid)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    my $delmaterial = $self -> {"materials"} -> check_permission($material -> {"metadata_id"},
                                                                 $userid,
                                                                 "materials.addmaterials");
    if(!$delmaterial) {
        $self -> log("error:materials:delmat", "Permission denied when attempting delete material $materialid");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APIDELMAT_PERMS"));
    }

    $self -> {"materials"} -> delete_material($self -> {"courseid"}, $sectionid, $materialid, $userid)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));

    $self -> log("materials:delmat", "Material delete complete");

    return { "response" => {"delete" => "ok"} };
}


## @method $ _build_api_materialorder_response()
# Reorder the sections in the materials page for the current course, if permitted.
#
# @return A reference to a hash containing the API response.
sub _build_api_materialorder_response {
    my $self = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    # Check that the user even has permission to sort.
    $self -> log("materials:materialorder", "User attempting to reorder materials");

    my $metadataid = $self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"});
    if(!$self -> {"materials"} -> check_permission($metadataid, $userid, "materials.sortlist")) {
        $self -> log("error:materials:sectionorder", "Permission denied when attempting to reorder materials");
        return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_MATERIALS_APISORTSEC_PERMS"));
    }
    my $viewhidden = $self -> {"materials"} -> check_permission($metadataid, $userid, "materials.viewhidden");

    # sort out the id list
    my $idlist = $self -> {"cgi"} -> param("idlist");
    my @ids = split(/,/, $idlist);
    foreach my $id (@ids) {
        # Pull the section and material out of the list
        my ($secid, $matid, $pos) = $id =~ /^secdata-(\d+)-mat-(\d+)-pos-(\d+)$/;
        next unless(defined($secid) && defined($matid) && defined($pos));

        $self -> log("materials:materialorder", "Set material $matid to position $pos in section $secid");
        $self -> {"materials"} -> set_material_order($self -> {"courseid"}, $secid, $matid, $pos)
            or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"materials"} -> {"errstr"}}));
    }

    $self -> log("materials:materialorder", "Material reorder complete");

    return { "response" => {"sort" => "ok"} };
}


# ============================================================================
#  Interface

## @method $ extra_header()
# Produce a string containing any javascript/css directives that need to be included in the
# page header.
#
# @return A strign containing html to include in the page header
sub extra_header {
    my $self  = shift;
    my $extra = $self -> {"template"} -> load_template("feature/materials/extrahead.tem");

    if($self -> {"matmodules"}) {
        foreach my $mat (keys(%{$self -> {"matmodules"}})) {
            $extra .= $self -> {"matmodules"} -> {$mat} -> extra_header()
                if($self -> {"matmodules"} -> {$mat} -> can('extra_header'));
        }
    }

    return $extra;
}


## @method $ section_display(materialid)
# Produce the string containing this block's 'section fragment' if it has one. By default,
# this will return a string containing an error message. If section fragment content is
# needed, this must be overridden in the subclass.
#
# @param materialid The ID of the material to display.
# @return The string containing this block's section content fragment.
sub section_display {
    my $self = shift;

    return "<p class=\"error\">".$self -> {"template"} -> replace_langvar("BLOCK_SECTION_DISPLAY")."</p>";
}


## @method $ block_display()
# Produce the string containing this block's 'block fragment' if it has one. By default,
# this will return a string containing an error message. If block fragment content is
# needed, this must be overridden in the subclass.
#
# @return The string containing this block's content fragment.
sub block_display {
    my $self = shift;

    return "<p class=\"error\">".$self -> {"template"} -> replace_langvar("BLOCK_BLOCK_DISPLAY")."</p>";
}


## @method $ page_display()
# Produce the string containing this block's full page content. This generates
# a course news page, including all navigation and decoration.
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;
    my ($content, $extrahead, $title);

    # Confirm that the user is logged in and has access to the course
    # ALL FEATURES SHOULD DO THIS BEFORE DOING ANYTHING ELSE!!
    my $error = $self -> check_login_courseview(0);
    return $error if($error);

    # Exit with a permission error unless the user has permission to read
    my $canread = $self -> {"materials"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                             $self -> {"session"} -> get_session_userid(),
                                                             "materials.view");
    if(!$canread) {
        $self -> log("error:materials:permission", "User does not have permission to view materials in course");

        my $userbar = $self -> {"module"} -> load_module("AATL::Userbar");
        my $message = $self -> {"template"} -> message_box("{L_FEATURE_MATERIALS_VIEWPERM_TITLE}",
                                                           "error",
                                                           "{L_FEATURE_MATERIALS_VIEWPERM}",
                                                           "",
                                                           undef,
                                                           "errorcore",
                                                           [ {"message" => $self -> {"template"} -> replace_langvar("SITE_CONTINUE"),
                                                              "colour"  => "blue",
                                                              "action"  => "location.href='".$self -> build_url(block => "news")."'"} ]);

        return $self -> {"template"} -> load_template("error/general.tem",
                                                      {"***title***"     => "{L_FEATURE_MATERIALS_VIEWPERM_TITLE}",
                                                       "***message***"   => $message,
                                                       "***extrahead***" => "",
                                                       "***userbar***"   => $userbar -> block_display(),
                                                      })
    }

    # Is this an API call, or a normal materials page call?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {
        my @pathinfo = $self -> {"cgi"} -> param('pathinfo');

        # If the third element of the pathinfo is defined then it is a call to a materials submodule. In theory.
        if(defined($pathinfo[2])) {
            my $matmodule = $self -> {"materials"} -> load_materials_module($pathinfo[2]);

            # Let the material module handle the request
            if($matmodule) {
                return $matmodule -> page_display();

            # No matching material module? Give up.
            } else {
                return $self -> api_html_response($self -> api_errorhash('bad_op',
                                                                         $self -> {"template"} -> replace_langvar("API_BAD_MODULE")));
            }

        # Otherwise it's a Materials-page ajax call. Dispatch to appropriate handlers.
        } else {
            given($apiop) {
                when("addsection")    { return $self -> api_html_response($self -> _build_api_addsection_response()); }
                when("addmatform")    { return $self -> api_html_response($self -> _build_api_addmatform_response()); }
                when("addmat")        { return $self -> api_html_response($self -> _build_api_addmat_response()); }
                when("delsection")    { return $self -> api_response($self -> _build_api_delsection_response()); }
                when("editsection")   { return $self -> api_response($self -> _build_api_editsection_response()); }
                when("sectionorder")  { return $self -> api_response($self -> _build_api_sectionorder_response()); }
                when("defvis")        { return $self -> api_response($self -> _build_api_defaultvisible_response()); }
                when("defopen")       { return $self -> api_response($self -> _build_api_defaultopen_response()); }
                when("delmat")        { return $self -> api_response($self -> _build_api_deletemat_response()); }
                when("materialorder") { return $self -> api_response($self -> _build_api_materialorder_response()); }
                default {
                    return $self -> api_html_response($self -> api_errorhash('bad_op',
                                                                             $self -> {"template"} -> replace_langvar("API_BAD_OP")))
                }
            }
        }
    } else {
        # Dispatch to materials page generation code
        ($content, $extrahead) = $self -> _build_section_list();

        # User has access, generate the materials page for the course.
        return $self -> generate_course_page("{L_FEATURE_MATERIALS_TITLE}", $content, $extrahead);
    }
}

1;
