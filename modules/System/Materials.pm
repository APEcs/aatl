## @file
# This file contains the implementation of the AATL materials model.
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
#  Creation/Cleanup

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


## @method void clear()
# Remove any circular references this module may possess. This must be called
# prior to exit to ensure that circular references do not prevent proper cleanup.
# In particular, instances of this class contain a cache of materials module
# instances, each of which contains a reference to this class.
sub clear() {
    my $self = shift;

    if($self -> {"modulecache"}) {
        foreach my $modname (keys(%{$self -> {"modulecache"}})) {
            $self -> {"modulecache"} -> {$modname} -> {"materials"} = undef;
        }
        $self -> {"modulecache"} = undef;
    }
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
    # context for the section
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


## @method $ delete_section($courseid, $sectionid, $userid)
# Mark the specified section as deleted by the provided user, if it is not already
# deleted.
#
# @param courseid  The ID of the course containing the section to delete.
# @param sectionid The ID of the section to mark as deleted.
# @param userid    The ID of the user doing the deletion.
# @return true on success, undef on error.
sub delete_section {
    my $self      = shift;
    my $courseid  = shift;
    my $sectionid = shift;
    my $userid    = shift;

    $self -> clear_error();

    my $nukeh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::material_sections"}."`
                                             SET deleted = UNIX_TIMESTAMP(), deleted_id = ?
                                             WHERE id = ?
                                             AND course_id = ?
                                             AND deleted IS NULL");
    my $result = $nukeh -> execute($userid, $sectionid, $courseid);
    return $self -> self_error("Unable to perform section delete: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Section delete failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method $ edit_section($courseid, $sectionid, $title)
# Update the title of the specified section to the supplied string.
#
# @param courseid  The ID of the course containing the section to edit.
# @param sectionid The ID of the section to edit.
# @param title     The new title string to set for the section
# @return true on success, undef on error.
sub edit_section {
    my $self      = shift;
    my $courseid  = shift;
    my $sectionid = shift;
    my $title     = shift;

    $self -> clear_error();

    my $titleh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::material_sections"}."`
                                              SET title = ?
                                              WHERE id = ?
                                              AND course_id = ?
                                              AND deleted IS NULL");
    my $result = $titleh -> execute($title, $sectionid, $courseid);
    return $self -> self_error("Unable to perform section update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Section update failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method $ set_section_visible($courseid, $sectionid, $visible)
# Update the visibility setting of the specified section
#
# @param courseid  The ID of the course containing the section to edit.
# @param sectionid The ID of the section to edit.
# @param visible   Should the section be visible? Should be 0 (invisible), or 1 (visible)
# @return true on success, undef on error.
sub set_section_visible {
    my $self      = shift;
    my $courseid  = shift;
    my $sectionid = shift;
    my $visible   = shift;

    $self -> clear_error();

    my $titleh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::material_sections"}."`
                                              SET visible = ?
                                              WHERE id = ?
                                              AND course_id = ?
                                              AND deleted IS NULL");
    my $result = $titleh -> execute($visible, $sectionid, $courseid);
    return $self -> self_error("Unable to perform section update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Section update failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method $ set_section_opened($courseid, $sectionid, $opened)
# Update the default open/closed setting of the specified section
#
# @param courseid  The ID of the course containing the section to edit.
# @param sectionid The ID of the section to edit.
# @param opened   Should the section be opened? Should be 0 (closed), or 1 (opened)
# @return true on success, undef on error.
sub set_section_opened {
    my $self      = shift;
    my $courseid  = shift;
    my $sectionid = shift;
    my $opened    = shift;

    $self -> clear_error();

    my $titleh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::material_sections"}."`
                                              SET open = ?
                                              WHERE id = ?
                                              AND course_id = ?
                                              AND deleted IS NULL");
    my $result = $titleh -> execute($opened, $sectionid, $courseid);
    return $self -> self_error("Unable to perform section update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Section update failed, no rows inserted") if($result eq "0E0");

    return 1;
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

    $self -> clear_error();

    my $secth = $self -> {"dbh"} -> prepare("SELECT *
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material_sections"}."`
                                             WHERE id = ?
                                             AND deleted IS NULL");
    $secth -> execute($sectionid)
        or return $self -> self_error("Unable to execute section lookup query: ".$self -> {"dbh"} -> errstr);

    return $secth -> fetchrow_hashref() || $self -> self_error("Unknown section requested");
}


## @method $ get_section_metadataid($courseid, $sectionid)
# Obtain the metadata context id for a specified section.
#
# @param sectionid The ID of the section to fetch the data for.
# @return The section metadata id on success, undef on error.
sub get_section_metadataid {
    my $self      = shift;
    my $courseid  = shift;
    my $sectionid = shift;

    $self -> clear_error();

    my $secth = $self -> {"dbh"} -> prepare("SELECT metadata_id
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material_sections"}."`
                                             WHERE id = ?
                                             AND course_id = ?
                                             AND deleted IS NULL");
    $secth -> execute($sectionid, $courseid)
        or return $self -> self_error("Unable to execute section metadataid query: ".$self -> {"dbh"} -> errstr);

    my $secdata = $secth -> fetchrow_arrayref()
        or return $self -> self_error("Unknown section requested");

    return $secdata -> [0];
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


## @method $ get_section_materiallist($courseid, $section, $show_hidden)
# Generate a list of materials IDs and modules in the specified section to present
# to the user.
#
# @param courseid    The ID of the course to fetch materials for.
# @param sectionid   The ID of the section containing the materials to fetch
# @param show_hidden Include sections that are marked as invisible.
# @return A reference to an array of hashrefs containing material IDs and module names,
#         sorted by their sort positions, undef on error.
sub get_section_materiallist {
    my $self        = shift;
    my $courseid    = shift;
    my $sectionid   = shift;
    my $show_hidden = shift;

    $self -> clear_error();

    print STDERR "get_section_materiallist($courseid, $sectionid, $show_hidden)";
    my $secth = $self -> {"dbh"} -> prepare("SELECT mats.id, mods.module_name
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material_materials"}."` AS mats,
                                                  `".$self -> {"settings"} -> {"database"} -> {"feature::material_modules"}."` AS mods
                                             WHERE mats.course_id = ?
                                             AND mats.section_id = ?
                                             AND mats.deleted IS NULL ".
                                            ($show_hidden ? "" : "AND mats.visible = 1 ").
                                            "AND mods.id = mats.type_id
                                             ORDER BY sort_position");
    $secth -> execute($courseid, $sectionid)
        or return $self -> self_error("Unable to execute materials list query: ".$self -> {"dbh"} -> errstr);

    return $secth -> fetchall_arrayref({});
}


# ============================================================================
#  Material listing/manglement

## @method $ add_material($courseid, $sectionid, $userid, $typeid, $title)
# Add a new material header. This creates a basic material header using the values
# supplied, it does not attempt to do any material-specific operations! Note that
# this does not attempt to perform any permissions checks on the addition: the caller
# is assumed to have done these!
#
# @param courseid  The ID of the course the material is being added to.
# @param sectionid The ID of the section the material should be added to.
# @param userid    The ID of the user adding the material.
# @param typeid    The ID of the material type
# @param title     The title to set for the material.
# @return The new material header ID on success, undef on error.
sub add_material {
    my $self      = shift;
    my $courseid  = shift;
    my $sectionid = shift;
    my $userid    = shift;
    my $typeid    = shift;
    my $title     = shift;

    $self -> clear_error();

    # Get the ID of the section metadata context, so it can be used to make a new
    # context for the material
    my $parentid = $self -> get_section_metadataid($courseid, $sectionid)
        or return $self -> self_error("Unable to obtain section metadata id: ".$self -> {"errstr"});

    my $metadataid = $self -> {"metadata"} -> create($parentid)
        or return $self -> self_error("Unable to create new metadata context: ".$self -> {"metadata"} -> {"errstr"});

    # Work out where to add the material in the list
    my $newpos = $self -> _get_max_material_sortpos($courseid, $sectionid);
    return undef if(!defined($newpos));
    ++$newpos;

    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::material_materials"}."`
                                            (metadata_id, course_id, section_id, created, creator_id, type_id, title, sort_position)
                                            VALUES(?, ?, ?, UNIX_TIMESTAMP(), ?, ?, ?, ?)");
    my $result = $newh -> execute($metadataid, $courseid, $sectionid, $userid, $typeid, $title, $newpos);
    return $self -> self_error("Unable to perform material insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Material insert failed, no rows inserted") if($result eq "0E0");

    # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
    #        Try to find a decent solution for this mess...
    my $materialid = $self -> {"dbh"} -> {"mysql_insertid"}
        or return $self -> self_error("Unable to obtain new section row id");

    return $materialid;
}


## @method $ delete_material($courseid, $sectionid, $materialid, $userid)
# Mark the specified material as deleted by the provided user, if it is not already
# deleted.
#
# @param courseid   The ID of the course containing the section to delete.
# @param sectionid  The ID of the section containing the material to mark as deleted.
# @param materialid The ID of the material to mark as deleted.
# @param userid     The ID of the user doing the deletion.
# @return true on success, undef on error.
sub delete_material {
    my $self       = shift;
    my $courseid   = shift;
    my $sectionid  = shift;
    my $materialid = shift;
    my $userid     = shift;

    $self -> clear_error();

    my $nukeh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::material_materials"}."`
                                             SET deleted = UNIX_TIMESTAMP(), deleted_id = ?
                                             WHERE course_id = ?
                                             AND section_id = ?
                                             AND id = ?
                                             AND deleted IS NULL");
    my $result = $nukeh -> execute($userid, $courseid, $sectionid, $materialid);
    return $self -> self_error("Unable to perform material delete: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Material delete failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method $ set_material_dataid($courseid, $sectionid, $materialid, $dataid)
# Update the data ID associated with the specified material. The ID is a free index
# into any data table the material module may manage.
#
# @param courseid   The ID of the course containing the material to edit.
# @param sectionid  The ID of the section containing the material to edit.
# @param materialid The ID of the material to edit.
# @param dataid     The data ID to set for this material (may be undef)
# @return true on success, undef on error.
sub set_material_dataid {
    my $self       = shift;
    my $courseid   = shift;
    my $sectionid  = shift;
    my $materialid = shift;
    my $dataid     = shift;

    $self -> clear_error();

    my $titleh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::material_materials"}."`
                                              SET type_data_id = ?
                                              WHERE id = ?
                                              AND course_id = ?
                                              AND section_id = ?
                                              AND deleted IS NULL");
    my $result = $titleh -> execute($dataid, $materialid, $courseid, $sectionid);
    return $self -> self_error("Unable to perform material dataid update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Material dataid update failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method $ get_material($courseid, $sectionid, $materialid)
# Obtain the header data for a specified material. Note that this does not (indeed,
# can not!) pull in additional type-secific data.
#
# @param courseid   The ID of the course the material is in.
# @param sectionid  The ID of the section the material is in.
# @param materialid The ID of the material to fetch the header data for.
# @return A reference to a hash containing the material data on success,
#         undef on error.
sub get_material {
    my $self = shift;
    my $courseid   = shift;
    my $sectionid  = shift;
    my $materialid = shift;

    $self -> clear_error();

    my $math = $self -> {"dbh"} -> prepare("SELECT *
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material_materials"}."`
                                            WHERE course_id = ?
                                            AND section_id = ?
                                            AND id = ?
                                            AND deleted IS NULL");
    $math -> execute($courseid, $sectionid, $materialid)
        or return $self -> self_error("Unable to execute material lookup query: ".$self -> {"dbh"} -> errstr);

    return $math -> fetchrow_hashref() || $self -> self_error("Unknown material requested");
}


# ============================================================================
#  Materials subclass related

## @method $ load_materials_module($modulename)
# Attempt to load an create an instance of a Materials module. Note that this will cache
# loaded and created modules, reducing the overhead of calling this to load the same module
# to a single return after the first call.
#
# @param modulename The name of the materials module to load.
# @param nocache    If true, force instantiation of a new module, even if one is already
#                   cached. This defaults to false, and should be used with extreme care.
# @return A reference to an instance of the requested materials module on success,
#         undef on error.
sub load_materials_module {
    my $self       = shift;
    my $modulename = shift;
    my $nocache    = shift;

    $self -> clear_error();

    return $self -> {"modulecache"} -> {$modulename} if($self -> {"modulecache"} -> {$modulename} && !$nocache);

    my $modh = $self -> {"dbh"} -> prepare("SELECT perl_module
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material_modules"}."`
                                            WHERE module_name = ?");
    $modh -> execute($modulename)
        or return $self -> self_error("Unable to execute materials module lookup: ".$self -> {"dbh"} -> errstr);

    my $modname = $modh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch module id for $modulename: entry does not exist");

    my $module = $self -> {"module"} -> load_module($modname -> [0],
                                                    typename  => $modulename,
                                                    courseid  => $self -> {"courseid"},
                                                    materials => $self);

    # Cache the module if possible
    $self -> {"modulecache"} -> {$modulename} = $module unless($nocache);

    return $module;
}


## @method $ get_section_list()
# Generate an optionlist containing the names and ids of available materials
# modules.
#
# @return A reference to an array of hashrefs containing the materials modules,
#         undef on error.
sub get_module_optionlist {
    my $self = shift;
    $self -> clear_error();

    my $modh = $self -> {"dbh"} -> prepare("SELECT module_name AS value, title AS name
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material_modules"}."`
                                            ORDER BY module_name");
    $modh -> execute()
        or return $self -> self_error("Unable to execute materials module list lookup: ".$self -> {"dbh"} -> errstr);

    return $modh -> fetchall_arrayref({})
        or $self -> self_error("Unable to fetch materials module list: no modules defined");
}


## @method $ get_material_typeid($type)
# Given a material type, obtain the ID of the material module implementation for that
# type.
#
# @param type The name of the material type to obtain the ID of.
# @return The ID of the material type module, or undef on error.
sub get_material_typeid {
    my $self = shift;
    my $type = shift;

    $self -> clear_error();

    my $modh = $self -> {"dbh"} -> prepare("SELECT id
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material_modules"}."`
                                            WHERE module_name = ?");
    $modh -> execute($type)
        or return $self -> self_error("Unable to execute materials module lookup: ".$self -> {"dbh"} -> errstr);

    my $modid = $modh -> fetchrow_arrayref()
        or return $self -> self_error("Request for non-existent material type $type");

    return $modid -> [0];
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


## @method private $ _get_max_material_sortpos($courseid, $sectionid)
# Obtain the maximum used material sort position in the specified section. This will
# return the highest sort position value set for materials in the section with the
# provided ID, or zero if there are no materials in the section.
#
# @param courseid  The ID of the course to get the maximum material sort pos value for.
# @param sectionid The ID of the section to get the maximum material sort pos value for.
# @return The maximum sort position value used, 0 if no position is set, undef on error.
sub _get_max_material_sortpos {
    my $self      = shift;
    my $courseid  = shift;
    my $sectionid = shift;

    $self -> clear_error();

    # Fetch the maximum sort position, ignoring deleted entries.
    my $posh = $self -> {"dbh"} -> prepare("SELECT MAX(sort_position)
                                            FROM  `".$self -> {"settings"} -> {"database"} -> {"feature::material_materials"}."`
                                            WHERE course_id = ?
                                            AND section_id = ?
                                            AND deleted IS NULL");
    $posh -> execute($courseid, $sectionid)
        or return $self -> self_error("Unable to execute material sort position query: ".$self -> {"dbh"} -> errstr);

    my $pos = $posh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch maximum sort position row. This should not happen.");

    # The result is either a Non-NULL value for the max, or we make it zero.
    return $pos -> [0] || 0;
}

1;
