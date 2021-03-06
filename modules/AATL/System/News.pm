## @file
# This file contains the implementation of the AATL news post handling engine.
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
# This class encapsulates operations involving news posts in the system.
package AATL::System::News;

use strict;
use base qw(Webperl::SystemModule);

# ==============================================================================
#  Creation

## @cmethod $ new(%args)
# Create a new News object to manage news post creation and lookup.
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
# @return A new News object, or undef if a problem occured.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_);
    return undef if(!$self);

    # Check that the required objects are present
    return Webperl::SystemModule::set_error("No roles object available.")    if(!$self -> {"roles"});
    return Webperl::SystemModule::set_error("No course object available.")   if(!$self -> {"courses"});
    return Webperl::SystemModule::set_error("No metadata object available.") if(!$self -> {"metadata"});

    return $self;
}


# ============================================================================
#  Permissions layer

## @method $ check_permission($metadataid, $userid, $request, $rolelimit)
# Determine whether the user has the ability to perform the requested news action.
# This will check the user's capabilities in the metadata context supplied, and
# return true if the user is able to perform the requested action, false if they are not.
#
# @param metadataid The ID of the metadata context to check the user's permissions in. Should
#                   either be a news post context, or a course context.
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
    $request = "news.$request" unless($request =~ /^news\./);

    # Determine whether the user has the capability
    return $self -> {"roles"} -> user_has_capability($metadataid, $userid, $request, $rolelimit);
}


# ============================================================================
#  Creation and editing

## @method $ create_post($courseid, $userid, $subject, $message, $sticky)
# Create a new news entry using the values provided. This will create a new news
# post at the current time.
#
# @param courseid The ID of the course the news entry is being posted to.
# @param userid   The ID of the user creating the post.
# @param subject  The post subject.
# @param message  The message to show in the post body.
# @param sticky   Should the message appear at the top of the news page at all times?
# @return True on success, undef on error.
sub create_post {
    my $self     = shift;
    my $courseid = shift;
    my $userid   = shift;
    my $subject  = shift;
    my $message  = shift;
    my $sticky   = shift;

    $self -> clear_error();

    # Get the ID of the course metadata context, so it can be used to make a new
    # context for the post
    my $parentid = $self -> {"courses"} -> get_course_metadataid($courseid)
        or return $self -> self_error("Unable to obtain course metadata id: ".$self -> {"courses"} -> {"errstr"} || "Course does not exist");

    my $metadataid = $self -> {"metadata"} -> create($parentid)
        or return $self -> self_error("Unable to create new metadata context: ".$self -> {"metadata"} -> {"errstr"});

    my $now = time();

    # Make a new news post, with no postid
    my $newsid = $self -> _new_news($metadataid, $courseid, $userid, $now, $sticky)
        or return undef;

    # Set the news post.
    return $self -> edit_post($newsid, $userid, $subject, $message, $now);
}


## @method $ edit_post($newsid, $userid, $subject, $message, $sticky)
# Create a new post and attach it to an existing news entry, replacing the old
# post for that entry.
#
# @param newsid  The ID of the news entry to attach a new post to.
# @param userid  The ID of the user creating the new post.
# @param subject The post subject.
# @param message The message to show in the post body.
# @param sticky  Should the message appear at the top of the news page at all times?
# @return True on success, undef on error.
sub edit_post {
    my $self    = shift;
    my $newsid  = shift;
    my $userid  = shift;
    my $subject = shift;
    my $message = shift;
    my $sticky  = shift;

    $self -> clear_error();

    # Make a new post body
    my $postid = $self -> _new_post($newsid, $userid, $subject, $message)
        or return undef;

    # Update the sticky mode
    $self -> _set_sticky($newsid, $sticky)
        or return undef;

    # Update the news post postid
    return $self -> _set_news_current_postid($newsid, $postid);
}


## @method $ delete_post($newsid, $userid)
# Mark the specified news post as deleted. Note that this will not actually delete
# the post, simply mark it as deleted so it won't show up in normal listings.
#
# @param newsid The id of the news entry to mark as deleted.
# @param userid The ID of the user deleting the entry.
# @param true on success, undef on error.
sub delete_post {
    my $self   = shift;
    my $newsid = shift;
    my $userid = shift;

    return $self -> _delete_news($newsid, $userid);
}


# ============================================================================
#  Listing code.

## @method $ get_post($newsid, $edithist)
# Obtain the data for a news entry, including its current post and potentially.
# any edit history.
#
# @param newsid   The ID of the news post to obtain.
# @param edithist If set to true, the returned hash contains a 'edithist' key,
#                 the value of which is the complete edit history of the news
#                 entry, with post updates sorted in reverse chronological order.
# @return A reference to a hash containing the post data on success, undef on error.
sub get_post {
    my $self     = shift;
    my $newsid   = shift;
    my $edithist = shift;

    return $self -> _get_news_entry($newsid, $edithist);
}


## @method $ get_news_posts($courseid, $offset, $count)
# Obtain a list of at most $count news posts from the specified course, starting
# with from the specified offset. This will pull a number of news posts, newest first,
# made in the specified course, and return them in an array of hashrefs.
#
# @param courseid The ID of the course to fetch news posts from.
# @param offset   The offset from the start of the posts list to start fetching from.
#                 (0 = from the beginning).
# @param count    The number of posts to fetch.
# @return A reference to an array of post data hashes on success, undef on error.
sub get_news_posts {
    my $self      = shift;
    my $courseid  = shift;
    my $offset    = shift;
    my $count     = shift;

    $self -> clear_error();

    # Offset must be a non-negative int
    return $self -> self_error("Illegal offset specified in call to get_news_posts()")
        unless(defined($offset) && $offset =~ /^\d+$/);

    # Count must be a positive, non-zero int
    return $self -> self_error("Illegal count specified in call to get_news_posts()")
        unless($count && $count =~ /^\d+$/);

    # Build a query to fetch news posts, and the post text.
    my $posth = $self -> {"dbh"} -> prepare("SELECT *
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"feature::news"}."` AS n,
                                                  `".$self -> {"settings"} -> {"database"} -> {"feature::news_posts"}."` AS p
                                             WHERE n.course_id = ?
                                             AND n.deleted IS NULL
                                             AND p.post_id = n.post_id
                                             ORDER BY n.sticky DESC, n.created DESC
                                             LIMIT $offset, $count");
    $posth -> execute($courseid)
        or return $self -> self_error("Unable to fetch post list ($courseid, $offset, $count): ".$self -> {"dbh"} -> errstr);

    # Happily, fetchall should do the job here...
    return $posth -> fetchall_arrayref({});
}


# ============================================================================
#  Internals

## @method $ _get_news_entry($newsid, $edithist)
# Obtain the data for a news entry, including its current post and potentially.
# any edit history.
#
# @param newsid   The ID of the news post to obtain.
# @param edithist If set to true, the returned hash contains a 'edithist' key,
#                 the value of which is the complete edit history of the news
#                 entry, with post updates sorted in reverse chronological order.
# @return A reference to a hash containing the post data on success, undef on error.
sub _get_news_entry {
    my $self     = shift;
    my $newsid   = shift;
    my $edithist = shift;

    my $newsh = $self -> {"dbh"} -> prepare("SELECT *
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"feature::news"}."` AS n,
                                                  `".$self -> {"settings"} -> {"database"} -> {"feature::news_posts"}."` AS p
                                             WHERE n.id = ?
                                             AND n.deleted IS NULL
                                             AND p.post_id = n.post_id");
    $newsh -> execute($newsid)
        or return $self -> self_error("Unable to fetch news entry ($newsid): ".$self -> {"dbh"} -> errstr);

    my $news = $newsh -> fetchrow_hashref()
        or return $self -> self_error("No data for news entry $newsid: entry does not exist?");

    # Has the user requested the edit history? If not, just return now...
    return $news unless($edithist);

    my $postsh = $self -> {"dbh"} -> prepare("SELECT *
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"feature::news_posts"}."`
                                              WHERE entry_id = ?
                                              ORDER BY edited DESC");
    $postsh -> execute($newsid)
        or return $self -> self_error("Unable to fetch posts for news entry $newsid: ".$self -> {"dbh"} -> errstr);

    # Shove the list of posts into the news entry data...
    $news -> {"edithist"} = $postsh -> fetchall_arrayref({});

    # This should never happen, but check it anyway
    return $self -> self_error("No post history found for news entry: bad news id $newsid?")
        unless($news -> {"edithist"} && scalar(@{$news -> {"edithist"}}));

    return $news;
}


## @method $ _new_news($metadataid, $courseid, $userid, $timestamp)
# Create a new entry in the Feature::news table to act as the 'header' for a
# news post.
#
# @param metadataid The ID of the metadata context to associate with the news post.
# @param courseid   The ID of the course the post is being made in (may be undef).
# @param userid     The ID of the user creating the post.
# @param sticky     Should the post stick at the top of the news list?
# @param timestamp  Optional unix typestamp to set for the entry. If not provided,
#                   the current time is used.
# @return The new post id on success, undef on error.
sub _new_news {
    my $self       = shift;
    my $metadataid = shift;
    my $courseid   = shift;
    my $userid     = shift;
    my $sticky     = shift;
    my $timestamp  = shift || time();

    $self -> clear_error();

    # Query to create a new news header
    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::news"}."`
                                            (metadata_id, course_id, created, creator_id, sticky)
                                            VALUES(?, ?, ?, ?, ?)");
    my $result = $newh -> execute($metadataid, $courseid, $timestamp, $userid, $sticky);
    return $self -> self_error("Unable to perform news insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("News insert failed, no rows inserted") if($result eq "0E0");

    # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
    #        Try to find a decent solution for this mess...
    my $newsid = $self -> {"dbh"} -> {"mysql_insertid"}
        or return $self -> self_error("Unable to obtain new news row id");

    # Attach to the metadata context
    $self -> {"metadata"} -> attach($metadataid)
        or return $self -> self_error("Error in metadata system: ".$self -> {"metadata"} -> {"errstr"});

    return $newsid;
}


## @method $ _delete_news($newsid, $userid)
# Mark the specified news post as deleted. Note that this will not actually delete
# the post, simply mark it as deleted so it won't show up in normal listings.
#
# @param newsid The ID of the news entry to mark as deleted.
# @param userid The ID of the user deleting the entry.
# @return true on success, undef on error.
sub _delete_news {
    my $self   = shift;
    my $newsid = shift;
    my $userid = shift;

    my $delh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::news"}."`
                                            SET deleted = UNIX_TIMESTAMP(), deleted_id = ?
                                            WHERE id = ?");
    my $result = $delh -> execute($userid, $newsid);
    return $self -> self_error("Unable to perform news delete: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("News delete failed, no rows updated") if($result eq "0E0");

    return 1;
}


## @method $ _get_news_current_postid($newsid)
# Obtain the ID of the post currently set for the specified news entry.
#
# @param newsid The ID of the news entry to get the post ID for.
# @return The post ID on success, 0 if the post has no ID set, undef on error.
sub _get_news_current_postid {
    my $self   = shift;
    my $newsid = shift;

    $self -> clear_error();

    my $newsh = $self -> {"dbh"} -> prepare("SELECT post_id FROM `".$self -> {"settings"} -> {"database"} -> {"feature::news"}."`
                                             WHERE id = ?");
    $newsh -> execute($newsid)
        or return $self -> self_error("Unable to execute post id query: ".$self -> {"dbh"} -> {"errstr"});

    my $news = $newsh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch last post id for news $newsid: news entry does not exist");

    return $news -> [0] || 0;
}


## @method $ _set_news_current_postid($newsid, $postid)
# Set the ID of the current post for the specified news entry.
#
# @param newsid The ID of the news entry to set the post ID for.
# @param postid The ID of the post to set as the current post.
# @return True on success, undef on error
sub _set_news_current_postid {
    my $self   = shift;
    my $newsid = shift;
    my $postid = shift;

    $self -> clear_error();

    my $seth = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::news"}."`
                                            SET post_id = ?
                                            WHERE id = ?");
    my $result = $seth -> execute($postid, $newsid);
    return $self -> self_error("Unable to perform news post update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("News post update failed, no rows inserted") if($result eq "0E0");

    return $self -> _get_news_entry($newsid);
}


## @method $ _set_sticky($newsid, $state)
# Set the stickiness of the specified news entry.
#
# @param newsid The ID of the news entry to set the stickiness of.
# @param state  The new sticky state, should be 0 or 1.
# @return True on success, undef on error
sub _set_sticky {
    my $self   = shift;
    my $newsid = shift;
    my $state  = shift;

    $self -> clear_error();

    my $seth = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::news"}."`
                                            SET sticky = ?
                                            WHERE id = ?");
    my $result = $seth -> execute($state, $newsid);
    return $self -> self_error("Unable to perform news sticky state update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("News sticky state update failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method $ _new_post($newsid, $userid, $subject, $message, $timestamp)
# Create a new news post entry, automatically recording whether it is an edit
# of a previous post or a new one.
#
# @param newsid    The ID of the news entry this is a post for.
# @param userid    The ID of the user posting the post.
# @param subject   The post subject.
# @param message   The message to show in the post body.
# @param timestamp Optional unix typestamp to set for the post. If not provided,
#                  the current time is used.
# @return The ID of the new post on success, undef on error.
sub _new_post {
    my $self      = shift;
    my $newsid    = shift;
    my $userid    = shift;
    my $subject   = shift;
    my $message   = shift;
    my $timestamp = shift || time();

    $self -> clear_error();

    # Check for any previous posts, bomb if there are any errors
    my $previd = $self -> _get_news_current_postid($newsid);
    return undef if(!defined($previd));

    # 0 makes no sense as a previd, so nuke it if it is zero
    undef $previd if(!$previd);

    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::news_posts"}."`
                                            (editor_id, entry_id, previous_id, subject, message, edited)
                                            VALUES(?, ?, ?, ?, ?, ?)");

    my $result = $newh -> execute($userid, $newsid, $previd, $subject, $message, $timestamp);
    return $self -> self_error("Unable to perform news post insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("News post insert failed, no rows inserted") if($result eq "0E0");

    # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
    #        Try to find a decent solution for this mess...
    my $postid = $self -> {"dbh"} -> {"mysql_insertid"}
        or return $self -> self_error("Unable to obtain new news post row id");

    return $postid;
}


1;
