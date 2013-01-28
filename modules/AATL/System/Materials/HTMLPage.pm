## @file
# This file contains the implementation of the AATL HTMLPage material model.
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
# This class encapsulates operations involving HTMLPage Materials in the system.
package AATL::System::Materials::HTMLPage;

use strict;
use base qw(AATL::System::Materials);

# ==============================================================================
#  Creation/Cleanup

## @cmethod $ new(%args)
# Create a new HTMLPage object to manage HTMLPage creation and lookup.
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
# @return A new HTMLPage object, or undef if a problem occured.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_);
    return undef if(!$self);

    # Check that the required objects are present
    return Webperl::SystemModule::set_error("No roles object available.")    if(!$self -> {"roles"});
    return Webperl::SystemModule::set_error("No course object available.")   if(!$self -> {"courses"});
    return Webperl::SystemModule::set_error("No metadata object available.") if(!$self -> {"metadata"});
    return Webperl::SystemModule::set_error("No module object available.")   if(!$self -> {"module"});

    return $self;
}


# ============================================================================
#  Addition, etc...

## @method $ add_material($headerid, $userid, $pagedata, $previousid)
# Add a new entry to the HTMLPage table for this material.
#
# @param headerid   The ID of the material this is additional data for.
# @param userid     The ID of the user adding the page.
# @param pagedata   The HTML text itself.
# @param previousid The ID of a previous version of this page (undef = none)
# @return The new HTMLPage id on success, undef on error
sub add_material {
    my $self       = shift;
    my $headerid   = shift;
    my $userid     = shift;
    my $pagedata   = shift;
    my $previousid = shift;

    $self -> clear_error();

    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::material::htmlpage"}."`
                                            (material_id, previous_id, edited, editor_id, htmldata)
                                            VALUES(?, ?, UNIX_TIMESTAMP(), ?, ?)");
    my $result = $newh -> execute($headerid, $previousid, $userid, $pagedata);
    return $self -> self_error("Unable to perform HTMLPage insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("HTMLPage insert failed, no rows inserted") if($result eq "0E0");

    # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
    #        Try to find a decent solution for this mess...
    my $pageid = $self -> {"dbh"} -> {"mysql_insertid"}
        or return $self -> self_error("Unable to obtain new section row id");

    return $pageid;
}


## @method $ get_section_data($courseid, $sectionid, $materialid)
# Obtain the information required to display the material section block. This
# pulls the data needed to build the section display block for the specified
# material from the database, and returns a reference to a hash containing the
# data.
#
# @param courseid   The ID of the course the material is in.
# @param sectionid  The ID of the section the material is in.
# @param materialid The ID of the material to get the section block data for.
# @return A reference to a hash containing the material's section block data on
#         success, undef on error.
sub get_section_data {
    my $self       = shift;
    my $courseid   = shift;
    my $sectionid  = shift;
    my $materialid = shift;

    # First, get the material header via materials
    my $material = $self -> {"materials"} -> get_material($courseid, $sectionid, $materialid)
        or return $self -> self_error("Unable to fetch material data: ".$self -> {"materials"} -> {"errstr"});

    # Now grab the additional data needed
    my $addh = $self -> {"dbh"} -> prepare("SELECT editor_id, edited, CHAR_LENGTH(htmldata) as length
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material::htmlpage"}."`
                                            WHERE id = ?");
    $addh -> execute($material -> {"type_data_id"})
        or return $self -> self_error("Unable to execute material data lookup query: ".$self -> {"dbh"} -> errstr);

    my $add = $addh -> fetchrow_hashref() || {};

    # Return the union of the two hashes.
    return { %$material, %$add};
}


## @method $ get_view_data($courseid, $sectionid, $materialid)
# Obtain the information required to display the material to the user. This
# pulls the data needed to build the view for the specified material from
# the database, and returns a reference to a hash containing the data.
#
# @param courseid   The ID of the course the material is in.
# @param sectionid  The ID of the section the material is in.
# @param materialid The ID of the material to get the view data for.
# @return A reference to a hash containing the material's view data on
#         success, undef on error.
sub get_view_data {
    my $self       = shift;
    my $courseid   = shift;
    my $sectionid  = shift;
    my $materialid = shift;

    # First, get the material header via materials
    my $material = $self -> {"materials"} -> get_material($courseid, $sectionid, $materialid)
        or return $self -> self_error("Unable to fetch material data: ".$self -> {"materials"} -> {"errstr"});

    # Now grab the additional data needed
    my $addh = $self -> {"dbh"} -> prepare("SELECT *, CHAR_LENGTH(htmldata) as length
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material::htmlpage"}."`
                                            WHERE id = ?");
    $addh -> execute($material -> {"type_data_id"})
        or return $self -> self_error("Unable to execute material data lookup query: ".$self -> {"dbh"} -> errstr);

    my $add = $addh -> fetchrow_hashref() || {};

    # Return the union of the two hashes.
    return { %$material, %$add};
}

1;
