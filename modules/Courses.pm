## @file
# This file contains the implementation of the AATL course handling engine.
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

## @class Courses
# This class encapsulates operations involving courses in the system.
package Courses;

use strict;
use base qw(SystemModule);

# ==============================================================================
#  Creation

## @cmethod $ new(%args)
# Create a new Courses object to manage course allocation and lookup.
# The minimum values you need to provide are:
#
# * dbh          - The database handle to use for queries.
# * settings     - The system settings object
# * metadata     - The system Metadata object.
# * roles        - The system Roles object.
# * logger       - The system logger object.
# * modules      - The system module/block loader object.
#
# You may also provide the following:
#
# * site_context - The ID of the site metadata context. This is the parent context
#                  of all courses in the system. If not specified, this defaults
#                  to `1`.
# * news_feature - The ID of the news feature in the features table. This defaults
#                  to `1`.
#
# @param args A hash of key value pairs to initialise the object with.
# @return A new Courses object, or undef if a problem occured.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(site_context => 1,
                                        news_feature => 1,
                                        @_);
    return undef if(!$self);

    # Check that the required objects are present
    return SystemModule::set_error("No metadata object available.") if(!$self -> {"metadata"});
    return SystemModule::set_error("No roles object available.") if(!$self -> {"roles"});
    return SystemModule::set_error("No module loader object available.") if(!$self -> {"modules"});

    return $self;
}

# ============================================================================
#  Permissions layer

## @method $ check_permission($courseid, $userid, $request, $rolelimit)
# Determine whether the user has the ability to perform the requested action on the
# course. This will check the user's capabilities in the metadata context associated
# with the course, and return true if the user is able to perform the requested action,
# and false if they are not.
#
# @note The capabilities `course.view` and `course.see` are treated specially by this
#       method: if the course access mode is set to `hidded` the request is internally
#       converted to `course.view_hidden` or `course.see_hidden`. Similarly, if the
#       course access mode is set to `closed`, the request is converted to
#       `course.view_closed` or `course.see_closed`. If the access mode is set to `open`,
#       or the request is not `course.view` or `course.see`, the request is not modified.
#
# @param courseid  The ID of the course to check the user's permissions in.
# @param userid    The ID of the user to check permissions of.
# @param request   The requested capability, should generally be of the form `course.action`,
#                  if the request does not start with `course.`, it will be appended.
# @param rolelimit An optional hash containing role ids as keys, and true or
#                  false as values. See Roles::user_has_capability() for more information.
# @return true if the user has the capability to perform the requested action, false if the
#         user does not, or undef on error.
sub check_permission {
    my $self      = shift;
    my $courseid  = shift;
    my $userid    = shift;
    my $request   = shift;
    my $rolelimit = shift;

    # Fix up the request if needed
    $request = "course.$request" unless($request =~ /^course\./);

    # Need the course data to obtain the metadata context, and possibly access mode
    my $course = $self -> _fetch_course($courseid)
        or return undef;

    # fix up view or see requests based on the access mode
    $request .= "_".$course -> {"access_mode"}
        if($course -> {"access_mode"} ne "open" && ($request eq "course.see" || $request eq "course.view"));

    # Determine whether the user has the capability
    return $self -> {"roles"} -> user_has_capability($course -> {"metadata_id"}, $userid, $request, $rolelimit);
}


# ============================================================================
#  Public interface - course creation, deletion, etc

## @method $ create($code, $title, $userid, $mode, $features)
# Create a new course entry in the system, initialising it as an empty container
# with the default features, unless a list of features to enable is provided.
#
# @param code     The course code, must be alphanumerics, - or _, and no longer than 32 characters.
# @param title    The course title, any content, 225 characters maximum.
# @param userid   The ID of the user creating the course.
# @param mode     The access mode, should be 'hidden', 'closed', or 'open'. Note that
#                 some users may still be able to see hidden courses (including, hopefully,
#                 the user who created the course!)
# @param features Optional reference to a hash of of feature IDs and enabled/disabled
#                 states: the keys of the hash are feature IDs, if the value for the
#                 key is true the feature is disabled, otherwise it is disabled. Features
#                 that do not appear in the hash are assumed to be disabled.
#                 Note that the News feature is **always enabled, and can not be disabled!**
# @return The new course ID on success, undef on failure.
sub create {
    my $self = shift;
    my ($code, $title, $userid, $mode, $features) = @_;

    $self -> clear_error();

    # Create a new metadata context for the course
    my $metadataid = $self -> {"metadata"} -> create($self -> {"site_context"});

    if($metadataid) {
        my $newh = $self -> {"dbh"} -> prepare("INSERT INTO ".$self -> {"settings"} -> {"database"} -> {"courses"}."
                                                (metadata_id, code, title, creator_id, created, access_mode)
                                                VALUES(?, ?, ?, ?, UNIX_TIMESTAMP(), ?)");
        my $rows = $newh -> execute($metadataid, $code, $title, $userid, $mode);

        if($rows) {
            if($rows ne "0E0") {
                # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
                #        Try to find a decent solution for this mess...
                my $courseid = $self -> {"dbh"} -> {"mysql_insertid"};
                if($courseid) {
                    # Set the enabled feature list.
                    return $courseid if($self -> set_features($courseid, $features));

                } else { # if($courseid) {
                    $self -> self_error("Unable to obtain id for course '$code'");
                }
            } else { # if($rows ne "0E0") {
                $self -> self_error("Course insert failed, no rows inserted");
            }
        } else { # if($rows) {
            $self -> self_error("Unable to perform course insert: ". $self -> {"dbh"} -> errstr);
        }
    } # if($metadataid) {
    return undef;
}



## @method $ get_courses($code)
# Obtain a list of course ids for courses that have the specified code set. This will
# return the list sorted latest-stated-first.
#
# @param code The course code to find courses of.
# @return A reference to an array of course ids, newest course first.
sub get_courses {
    my $self = shift;
    my $code = shift;

    my $courseh = $self -> {"dbh"} -> prepare("SELECT id FROM ".$self -> {"settings"} -> {"database"} -> {"courses"}."
                                               WHERE code LIKE ?
                                               ORDER BY started DESC");
    $courseh -> execute($code)
        or return $self -> self_error("Unable to execute course lookup: ".$self -> {"dbh"} -> errstr);

    # Can't sanely use fetchall_ here, so push results into an array
    my @results = ();
    while(my $course = $courseh -> fetchrow_arrayref()) {
        push(@results, $course -> [0]);
    }

    return \@results;
}


# ============================================================================
#  Feature control

## @method $ set_features($courseid, $features)
# Set the features active on a course. This will disable any features that do
# not appear in the specified features array, and enable any that do that are
# not already enabled.
#
# @note The news feature is **always enabled**, even if you try to disable it
#       in the features hash.
#
# @param courseid The ID of the course to modify the feature settings for.
# @param features A reference to a hash of features. Each key is a feature ID
#                 and the value determines whether the feature is enabled or not
#                 (true is enabled, false is disabled). If a feature is already
#                 enabled for the course, but does not appear in this hash, it
#                 will be disabled. If this is not supplied at all, the default
#                 feature list will be used instead.
# @return true on success, undef on error.
sub set_features {
    my $self     = shift;
    my $courseid = shift;
    my $features = shift; # Handle an undef feature list gracefully

    # Fall back on the default list of features if a list isn't specified.
    $features = $self -> _fetch_default_features() if(!defined($features));
    return undef if(!defined($features)); # give up if there's still no feature list.

    # You know I said that the news features is always enabled? I mean it.
    $features -> {$self -> {"news_feature"}} = 1;

    # Get the list of currently set features, so that ones not present in the features
    # hash can be deactivated
    my $set_features = $self -> _fetch_set_features($courseid);
    return undef if(!defined($set_features));

    # Traverse the set features, disabling any entries not present in the features
    # hash. This also creates a hash of enabled features to make the next pass easier
    my $already_enabled = {};
    foreach my $feature (@{$set_features}) {
        # If the feature is enabled and should be, record it as already enabled
        if($features -> {$feature -> {"id"}}) {
            $already_enabled -> {$feature -> {"id"}} = 1;

        # The feature is enabled, but shouldn't be - disable it
        } else {
            $self -> disable_feature($courseid, $feature -> {"id"})
                or return undef;
        }
    }

    # Now go through the list of features turning on any that aren't already enabled
    foreach my $featureid (keys(%{$features})) {
        next if(!$features -> {$featureid} || $already_enabled -> {$featureid});

        $self -> enable_feature($courseid, $featureid)
            or return undef;
    }

    return 1;
}


## @method $ enable_feature($courseid, $featureid)
# Turn on a feature in the specified course. This will enable the feature, and do any
# set-up work required to make it actually work. Note that this will determine whether
# feature is already enabled, and if it is it will do nothing.
#
# @param courseid  The ID of the course to enable the feature in.
# @param featureid The ID of the feature to enable.
# @return true on success, undef on error.
sub enable_feature {
    my $self      = shift;
    my $courseid  = shift;
    my $featureid = shift;

    # check whether the feature is already enabled.
    my $feature = $self -> _feature_enabled($courseid, $featureid);
    if($feature) {
        # attempt to re-enable a feature, shouldn't normally happen - log it
        $self -> {"logger"} -> log("warning", undef, undef, "Attempt to re-enable feature $featureid on course $courseid.");
        return 1;
    }

    # Feature is not enabled, load the block to handle it
    $feature = $self -> _fetch_feature($featureid);
    return undef if(!$feature);

    # Load the block to handle the feature
    my $block = $self -> {"modules"} -> new_module($feature -> {"block_name"});
    return $self -> self_error("Unable to load block for feature $featureid: ".$self -> {"modules"} -> {"errstr"}) if(!$block);

    # let the block do any gruntwork needed to enable the feature
    $block -> enable($courseid)
        or return $self -> self_error("Unable to enable feature $featureid in course $courseid: ".$block -> {"errstr"});

    # Feature has been set up, mark it as such
    my $activeh = $self -> {"dbh"} -> prepare("INSERT INTO ".$self -> {"settings"} -> {"database"} -> {"course_features"}."
                                               (course_id, feature_id)
                                               VALUES(?, ?)");
    my $rows = $activeh -> execute($courseid, $featureid);
    if(!$rows || $rows eq "0E0") {
        # Insert failed, so disable the feature again
        $block -> disable($courseid)
            or return $self -> self_error("Emergency disable of feature $featureid in course $courseid failed: ".$block -> {"errstr"});
        return $self -> self_error("Unable to perform feature enable: ". $self -> {"dbh"} -> errstr) if(!$rows);
        return $self -> self_error("Feature enable failed: no rows added") if($rows eq "0E0");
    }

    return 1;
}


## @method $ disable_feature($courseid, $featureid)
# Disable a feature in the specified course. This will disable the feature, and do
# any cleanup work required to remove the data. This will check that the feature is
# enabled, and if it is not it will do nothing.
#
# @param courseid  The ID of the course to disable the feature in.
# @param featureid The ID of the feature to disable.
# @return true on success, undef on error.
sub disable_feature {
    my $self      = shift;
    my $courseid  = shift;
    my $featureid = shift;

    # check whether the feature is enabled.
    my $feature = $self -> _feature_enabled($courseid, $featureid);
    if(!$feature) {
        # attempt to re-disable a feature, shouldn't normally happen - log it
        $self -> {"logger"} -> log("warning", undef, undef, "Attempt to re-disable feature $featureid on course $courseid.");
        return 1;
    }

    # Remove the block from the enabled list
    my $nukeh = $self -> {"dbh"} -> prepare("DELETE FROM ".$self -> {"settings"} -> {"database"} -> {"course_features"}."
                                             WHERE course_id = ?
                                             AND feature_id = ?");
    my $rows = $nukeh -> execute($courseid, $featureid);
    return $self -> self_error("Unable to perform feature disable: ". $self -> {"dbh"} -> errstr) if(!$rows);
    return $self -> self_error("Feature disable failed: no rows removed") if($rows eq "0E0");

    # Get the block to handle the feature
    my $block = $self -> {"modules"} -> new_module($feature -> {"block_name"});
    return $self -> self_error("Unable to load block for feature $featureid: ".$self -> {"modules"} -> {"errstr"}) if(!$block);

    # clean up
    $block -> disable($courseid)
        or return $self -> self_error("Unable to disable feature $featureid in course $courseid: ".$block -> {"errstr"});

    return 1;
}


# ============================================================================
#  Private functions - feature related methods

## @method private $ _fetch_default_features()
# Fetch a hash containing the default feature states for courses. This will
# go through the features table looking for entries that are marked as
# default_enabled and adding them to the hash.
#
# @return A reference to a hash of enabled features.
sub _fetch_default_features {
    my $self     = shift;
    my $features = {};

    my $enabledh = $self -> {"dbh"} -> prepare("SELECT id FROM ".$self -> {"settings"} -> {"database"} -> {"features"}."
                                                WHERE default_enabled = 1");
    $enabledh -> execute()
        or return $self -> self_error("Unable to execute default feature lookup: ".$self -> {"dbh"} -> errstr);

    while(my $feature = $enabledh -> fetchrow_arrayref()) {
        $features -> {$feature -> [0]} = 1;
    }

    return $features;
}


## @method private $ _fetch_set_features($courseid, $location)
# Fetch a list of features currently enabled for the specified course.
#
# @param courseid The ID of the course to fetch the active features list for.
# @param location Optional location to filter results on. Should either be undef
#                 or one of "sidebar", "toolbar", or "hidden".
# @return A reference to a list of hashrefs, each hashref contains the feature
#         data, undef on error.
sub _fetch_set_features {
    my $self     = shift;
    my $courseid = shift;
    my $location = shift;

    $self -> clear_error();

    my $seth = $self -> {"dbh"} -> prepare("SELECT f.*
                                            FROM ".$self -> {"settings"} -> {"database"} -> {"features"}." AS f,
                                                 ".$self -> {"settings"} -> {"database"} -> {"course_features"}." AS c
                                            WHERE c.course_id = ?
                                            AND f.id = c.feature_id ".
                                            ($location ? "AND f.location = ? " : "").
                                            "ORDER BY f.location, f.sort_order");
    my $result;
    if($location) {
        $result = $seth -> execute($courseid, $location);
    } else {
        $result = $seth -> execute($courseid);
    }
    return $self -> self_error("Unable to execute active feature lookup: ".$self -> {"dbh"} -> errstr) if(!$result);

    # This should be enough to get the data in the format needed...
    return $seth -> fetchrow_arrayref({});
}


## @method private $ _feature_enabled($courseid, $featureid)
# Determine whether the specified feature is enabled. If it is enabled, this will
# return a hash containing the feature's information (location, sort order, block name
# and so on).
#
# @param courseid  The ID of the course to check the feature against.
# @param featureid The ID of the feature to check.
# @return A reference to a hash contianing the feature data on success, undef on
#         error or if the feature is not enabled.
sub _feature_enabled {
    my $self      = shift;
    my $courseid  = shift;
    my $featureid = shift;

    $self -> clear_error();

    # Check, and pull in the feature data at the same time
    my $geth = $self -> {"dbh"} -> prepare("SELECT f.*
                                            FROM ".$self -> {"settings"} -> {"database"} -> {"features"}." AS f,
                                                 ".$self -> {"settings"} -> {"database"} -> {"course_features"}." AS c
                                            WHERE c.course_id = ?
                                            AND c.feature_id = ?
                                            AND f.id = c.feature_id");
    $geth -> execute($courseid, $featureid)
        or return $self -> self_error("Unable to execute course feature lookup: ".$self -> {"dbh"} -> errstr);

    # Can return the hashref as-is here. If the feature is not enabled, this will
    # return undef anyway.
    return $geth -> fetchrow_hashref();
}


## @method private $ _fetch_feature($featureid)
# A simple convenience function to fetch the data for a feature. This will
# look up the feature and return a reference to a hash containing the feature
# data if it is valid.
#
# @param featureid The ID of the feature to fetch the data for.
# @return A reference to a hash containing the feature data, if the ID matches
#         a valid feature record. undef on error or bad feature ID.
sub _fetch_feature {
    my $self      = shift;
    my $featureid = shift;

    $self -> clear_error();

    my $geth = $self -> {"dbh"} -> prepare("SELECT *
                                            FROM ".$self -> {"settings"} -> {"database"} -> {"features"}."
                                            WHERE id = ?");
    $geth -> execute($featureid)
        or return $self -> self_error("Unable to execute feature lookup: ".$self -> {"dbh"} -> errstr);

    return $geth -> fetchrow_hashref();
}


## @method private $ _fetch_course($courseid)
# A simple convenience function to fetch the data for a course. This will
# look up the course and return a reference to a hash containing the course
# data if it is valid.
#
# @param courseid The ID of the course to fetch the data for.
# @return A reference to a hash containing the course data, if the ID matches
#         a valid course record. undef on error or bad course ID.
sub _fetch_course {
    my $self     = shift;
    my $courseid = shift;

    $self -> clear_error();

    my $geth = $self -> {"dbh"} -> prepare("SELECT *
                                            FROM ".$self -> {"settings"} -> {"database"} -> {"courses"}."
                                            WHERE id = ?");
    $geth -> execute($courseid)
        or return $self -> self_error("Unable to execute course lookup: ".$self -> {"dbh"} -> errstr);

    return $geth -> fetchrow_hashref();
}

1;
