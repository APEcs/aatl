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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

## @class Feature::Materials
#
package Feature::Materials;

use strict;
use base qw(Feature);
use Utils qw(is_defined_numeric);
use System::Materials;

# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Overloaded constructor for QAForums, loads the System::QAForums model and other
# classes required to generate the forum pages.
#
# @param args A hash of values to initialise the object with. See the Block docs
#             for more information.
# @return A reference to a new Feature::QAForums object on success, undef on error.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_)
        or return undef;

    # Create a news model to work through.
    $self -> {"materials"} = System::Materials -> new(dbh      => $self -> {"dbh"},
                                                      settings => $self -> {"settings"},
                                                      logger   => $self -> {"logger"},
                                                      module   => $self -> {"module"},
                                                      roles    => $self -> {"system"} -> {"roles"},
                                                      metadata => $self -> {"system"} -> {"metadata"},
                                                      courses  => $self -> {"system"} -> {"courses"})
        or return SystemModule::set_error("Materials initialisation failed: ".$System::Materials::errstr);

    # FIXME: This will probably need to instantiate the tags feature to get at Feature::Tags::block_display().
    # $self -> {"tags"} = $self -> {"modules"} -> load_module("Feature::Tags");

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

    return { "materials.view"       => $self -> {"template"} -> replace_langvar("CAPABILITY_MATERIALS.VIEW"),
             "materials.viewhidden" => $self -> {"template"} -> replace_langvar("CAPABILITY_MATERIALS.VIEWHIDDEN"),
             "materials.addsection" => $self -> {"template"} -> replace_langvar("CAPABILITY_MATERIALS.ADDSECTION"),
           };
}


# ============================================================================
#  Section handling/listing

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
    my $permcacne = shift;
    my $temcache  = shift;

    # Build the section contents
    my $contents = ""; # TODO

    # Section admin bar and controls
    my $admin = ""; # $self -> _build_section_admin($section, $userid);
    my $controls = ""; # $self -> _build_section_controls($section, $userid);

    # Work out the classes to apply to the section
    my $section_class = "";
    $section_class .= "hidden" unless($section -> {"visible"});
    $section_class .= "closed" unless($section -> {"open"});

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
    my $viewhidden = $self -> {"materials"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                                $userid,
                                                                "materials.viewhidden");

    # Cache some templates for list generation
    my $temcache = { "section" => $self -> {"template"} -> load_template("feature/materials/section.tem"),
    };

    # And some permissions
    my $permcache = {
    };

    my $sections = $self -> {"materials"} -> get_section_list($self -> {"courseid"}, $viewhidden);
    my $sectionlist = "";
    foreach my $section (@{$sections}) {
        $sectionlist .= $self -> _build_section($section, $userid, $permcache, $temcache);
    }

    # Can the user add sections?
    my $addsection = $self -> {"materials"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                                $userid,
                                                                "materials.addsection");
    $addsection = $addsection ? "enabled" : "disabled";

    return ($self -> {"template"} -> load_template("feature/materials/sectionlist.tem",
                                                   {"***error***"   => $error,
                                                    "***entries***" => $sectionlist,
                                                    "***addopt***"  => $self -> {"template"} -> load_template("feature/materials/addsection_${addsection}.tem")
                                                   }),
            $self -> {"template"} -> load_template("feature/materials/extrahead.tem"));
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
    my $temcache = { "section" => $self -> {"template"} -> load_template("feature/materials/section.tem"),
    };

    # And some permissions
    my $permcache = {
    };

    return $self -> _build_section($section, $userid, $permcache, $temcache);
}


# ============================================================================
#  Interface

## @method $ section_display()
# Produce the string containing this block's 'section fragment' if it has one. By default,
# this will return a string containing an error message. If section fragment content is
# needed, this must be overridden in the subclass.
#
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

        my $userbar = $self -> {"module"} -> load_module("Feature::Userbar");
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

    # Is this an API call, or a normal news page call?
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
            if($apiop eq "addsection") {
                return $self -> api_html_response($self -> _build_api_addsection_response());
            } else {
                return $self -> api_html_response($self -> api_errorhash('bad_op',
                                                                         $self -> {"template"} -> replace_langvar("API_BAD_OP")))
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
