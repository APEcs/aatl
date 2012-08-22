## @file
# This file contains the implementation of the AATL QA Forum handling engine.
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

## @class System::Materials
# This class encapsulates operations involving Materials in the system.
package System::Materials;

use strict;
use base qw(SystemModule);
use List::Util qw(max);

# ==============================================================================
#  Creation

## @cmethod $ new(%args)
# Create a new Materials object to manage Materials creation and lookup.
# The minimum values you need to provide are:
#
# * dbh          - The database handle to use for queries.
# * settings     - The system settings object
# * logger       - The system logger object.
# * roles        - The system roles object.
# * courses      - The system courses object.
# * metadata     - The system metadata object.
#
# @param args A hash of key value pairs to initialise the object with.
# @return A new Materials object, or undef if a problem occured.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_);
    return undef if(!$self);

    # Check that the required objects are present
    return SystemModule::set_error("No roles object available.")    if(!$self -> {"roles"});
    return SystemModule::set_error("No course object available.")   if(!$self -> {"courses"});
    return SystemModule::set_error("No metadata object available.") if(!$self -> {"metadata"});
    return SystemModule::set_error("No module object available.")   if(!$self -> {"module"});

    return $self;
}


# ============================================================================
#  Permissions layer

## @method $ check_permission($metadataid, $userid, $request, $rolelimit)
# Determine whether the user has the ability to perform the requested Materials action.
# This will check the user's capabilities in the metadata context supplied, and
# return true if the user is able to perform the requested action, false if they are not.
#
# @param metadataid The ID of the metadata context to check the user's permissions in. Should
#                   either be a Materials post context, or a course context.
# @param userid     The ID of the user to check permissions of.
# @param request    The requested capability, should generally be of the form `course.action`,
#                   if the request does not start with `course.`, it will be appended.
# @param rolelimit  An optional hash containing role ids as keys, and true or
#                   false as values. See Roles::user_has_capability() for more information.
# @return true if the user has the capability to perform the requested action, false if the
#         user does not, or undef on error.
sub check_permission {
    my $self       = shift;
    my $metadataid = shift;
    my $userid     = shift;
    my $request    = shift;
    my $rolelimit  = shift;

    # Fix up the request if needed
    $request = "materials.$request" unless($request =~ /^materials\./);

    # Determine whether the user has the capability
    return $self -> {"roles"} -> user_has_capability($metadataid, $userid, $request, $rolelimit);
}


# ============================================================================
#  Section listing/manglement

## @method $ add_section($courseid, $userid, $title)
# Add a new, hidden, closed section to the specified course.
#
# @param courseid The ID of the course to add the section to.
# @param userid   The ID of the user adding the section.
# @param title    The title to set in the section header.
# @return The new section ID on success, undef on error.
sub add_section {
    my $self     = shift;
    my $courseid = shift;
    my $userid   = shift;
    my $title    = shift;

    $self -> clear_error();

    # Get the ID of the course metadata context, so it can be used to make a new
    # context for the post
    my $parentid = $self -> {"courses"} -> get_course_metadataid($courseid)
        or return $self -> self_error("Unable to obtain course metadata id: ".$self -> {"courses"} -> {"errstr"} || "Course does not exist");

    my $metadataid = $self -> {"metadata"} -> create($parentid)
        or return $self -> self_error("Unable to create new metadata context: ".$self -> {"metadata"} -> {"errstr"});

    # We need to put the new section after the current maximum (FIXME: potential
    # concurrent access race condition here. Is it worth addressing?)
    my $newpos = $self -> _get_max_section_sortpos($courseid);
    return undef if(!defined($newpos));
    ++$newpos;

    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::material_sections"}."`
                                            (metadata_id, course_id, created, creator_id, title, sort_position)
                                            VALUES(?, ?, UNIX_TIMESTAMP(), ?, ?, ?)");
    my $result = $newh -> execute($metadataid, $courseid, $userid, "$title: $newpos", $newpos);
    return $self -> self_error("Unable to perform section insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Section insert failed, no rows inserted") if($result eq "0E0");

    # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
    #        Try to find a decent solution for this mess...
    my $sectionid = $self -> {"dbh"} -> {"mysql_insertid"}
        or return $self -> self_error("Unable to obtain new section row id");

    return $sectionid;
}


## @method $ get_section($sectionid)
# Obtain the data for a specified section.
#
# @param sectionid The ID of the section to fetch the data for.
# @return A reference to a hash containing the section data on success,
#         undef on error.
sub get_section {
    my $self = shift;
    my $sectionid = shift;

    my $secth = $self -> {"dbh"} -> prepare("SELECT *
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material_sections"}."`
                                             WHERE id = ?
                                             AND deleted IS NULL");
    $secth -> execute($sectionid)
        or return $self -> self_error("Unable to execute section loopup query: ".$self -> {"dbh"} -> errstr);

    return $secth -> fetchrow_hashref() || $self -> self_error("Unknown section requested");
}


## @method $ get_section_list($courseid, $show_hidden)
# Generate a list of sections to present to the user. This does not include the contents
# of the section, merely the section title and metadata.
#
# @param courseid    The ID of the course to fetch sections for,
# @param show_hidden Include sections that are marked as invisible.
# @return A reference to an array of hashrefs containing sections, sorted by their
#         sort positions.
sub get_section_list {
    my $self        = shift;
    my $courseid    = shift;
    my $show_hidden = shift;

    $self -> clear_error();

    my $secth = $self -> {"dbh"} -> prepare("SELECT *
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material_sections"}."`
                                             WHERE course_id = ?
                                             AND deleted IS NULL ".
                                            ($show_hidden ? "" : "AND visible = 1 ").
                                            "ORDER BY sort_position");
    $secth -> execute($courseid)
        or return $self -> self_error("Unable to execute section list query: ".$self -> {"dbh"} -> errstr);

    return $secth -> fetchall_arrayref({});
}


## @method $ set_section_order($courseid, $sectionid, $position)
# Set the sort position for the sepcified section to the given position. This will not
# enforce any kind of position uniqueness - that's up to the caller to deal with!
#
# @param $courseid  The ID of the course to set section ordering in.
# @param $sectionid The section to change the order of.
# @param $position  The new section position
# @return true on success, undef on error
sub set_section_order {
    my $self      = shift;
    my $courseid  = shift;
    my $sectionid = shift;
    my $position  = shift;

    $self -> clear_error();

    my $posh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::material_sections"}."`
                                            SET sort_position = ?
                                            WHERE id = ?
                                            AND course_id = ?
                                            AND deleted IS NULL");
    my $result = $posh -> execute($position, $sectionid, $courseid);
    return $self -> self_error("Unable to perform section position update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Section position update failed, no rows inserted") if($result eq "0E0");

    return 1;
}


# ============================================================================
#  Materials subclass loader

## @method $ load_materials_module($modulename)
# Attempt to load an create an instance of a Materials module.
#
# @param modulename The name of the materials module to load.
# @return A reference to an instance of the requested materials module on success,
#         undef on error.
sub load_materials_module {
    my $self       = shift;
    my $modulename = shift;

    my $modh = $self -> {"dbh"} -> prepare("SELECT perl_module
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material_modules"}."`
                                            WHERE module_name = ?");
    $modh -> execute($modulename)
        or return $self -> self_error("Unable to execute materials module lookup: ".$self -> {"dbh"} -> errstr);

    my $modname = $modh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch module id for $modulename: entry does not exist");

    return $self -> {"module"} -> load_module($modname -> [0], { courseid => $self -> {"courseid"} });
}


# ============================================================================
#  Internals


## @method private $ _get_max_section_sortpos($courseid)
# Obtain the maximum used section sort position in the specified course. This will
# return the highest sort position value set for sections in the course with the
# provided ID, or zero if there are no sections.
#
# @param courseid The ID of the course to get the maximum section sort pos value for.
# @return The maximum sort position value used, 0 if no position is set, undef on error.
sub _get_max_section_sortpos {
    my $self     = shift;
    my $courseid = shift;

    $self -> clear_error();

    # Fetch the maximum sort position, ignoring deleted entries.
    my $posh = $self -> {"dbh"} -> prepare("SELECT MAX(sort_position)
                                            FROM  `".$self -> {"settings"} -> {"database"} -> {"feature::material_sections"}."`
                                            WHERE course_id = ?
                                            AND deleted IS NULL");
    $posh -> execute($courseid)
        or return $self -> self_error("Unable to execute section sort position query: ".$self -> {"dbh"} -> errstr);

    my $pos = $posh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch maximum sort position row. This should not happen.");

    # The result is either a Non-NULL value for the max, or we make it zero.
    return $pos -> [0] || 0;
}

1;
