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

## @class System::QAForums
# This class encapsulates operations involving QA Forums in the system.
package System::QAForums;

use strict;
use base qw(SystemModule);

# ==============================================================================
#  Creation

## @cmethod $ new(%args)
# Create a new QAForum object to manage QAForum post creation and lookup.
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
# @return A new QAForum object, or undef if a problem occured.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_);
    return undef if(!$self);

    # Check that the required objects are present
    return SystemModule::set_error("No roles object available.")    if(!$self -> {"roles"});
    return SystemModule::set_error("No course object available.")   if(!$self -> {"courses"});
    return SystemModule::set_error("No metadata object available.") if(!$self -> {"metadata"});

    return $self;
}


# ============================================================================
#  Permissions layer

## @method $ check_permission($metadataid, $userid, $request, $rolelimit)
# Determine whether the user has the ability to perform the requested QAForum action.
# This will check the user's capabilities in the metadata context supplied, and
# return true if the user is able to perform the requested action, false if they are not.
#
# @param metadataid The ID of the metadata context to check the user's permissions in. Should
#                   either be a QAForum post context, or a course context.
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
    $request = "qaforums.$request" unless($request =~ /^qaforums\./);

    # Determine whether the user has the capability
    return $self -> {"roles"} -> user_has_capability($metadataid, $userid, $request, $rolelimit);
}


# ============================================================================
#  Creation and editing

## @method $ create_question($courseid, $userid, $subject, $message, $tags)
# Create a new question using the values provided. This will create a new question
# thread at the current time.
#
# @param courseid The ID of the course the question is being posted to.
# @param userid   The ID of the user creating the question.
# @param subject  The question subject.
# @param message  The message to show in the question body.
# @param tags     A comma separated list of tag names to apply initially.
# @return True on success, undef on error.
sub create_question {
    my $self     = shift;
    my $courseid = shift;
    my $userid   = shift;
    my $subject  = shift;
    my $message  = shift;

    $self -> clear_error();

    # Get the ID of the course metadata context, so it can be used to make a new
    # context for the question
    my $parentid = $self -> {"courses"} -> get_course_metadataid($courseid)
        or return $self -> self_error("Unable to obtain course metadata id: ".$self -> {"courses"} -> {"errstr"} || "Course does not exist");

    my $metadataid = $self -> {"metadata"} -> create($parentid)
        or return $self -> self_error("Unable to create new metadata context: ".$self -> {"metadata"} -> {"errstr"});

    my $now = time();

    # Make a new question, with no postid
    my $qid = $self -> _new_question($metadataid, $courseid, $userid, $now)
        or return undef;

    # Set the queston text.
    return $self -> edit_question($qid, $userid, $subject, $message, $now);
}


## @method $ edit_question($questionid, $userid, $subject, $message)
# Create a new text and attach it to an existing question, replacing the old
# text for that entry.
#
# @param questionid The ID of the question to attach a new text to.
# @param userid     The ID of the user creating the new text.
# @param subject    The text subject.
# @param message    The message to show in the text body.
# @return True on success, undef on error.
sub edit_question {
    my $self       = shift;
    my $questionid = shift;
    my $userid     = shift;
    my $subject    = shift;
    my $message    = shift;

    $self -> clear_error();

    my $previd = $self -> _get_current_textid($questionid, "question");
    return undef unless(defined($previd));

    # Make a new text entry
    my $textid = $self -> _new_text($userid, $subject, $message, $previd)
        or return undef;

    # Update the question textid
    return $self -> _set_current_textid($questionid, "question", $textid);
}


## @method $ delete_question($questionid, $userid)
# Mark the specified question as deleted. Note that this will not actually delete
# the question, simply mark it as deleted so it won't show up in normal listings.
#
# @param questionid The id of the question to mark as deleted.
# @param userid     The ID of the user deleting the question.
# @param true on success, undef on error.
sub delete_question {
    my $self       = shift;
    my $questionid = shift;
    my $userid     = shift;

    return $self -> _delete($questionid, "question", $userid);
}


## @method $ flag_question($questionid, $userid)
# Set the flagged status on the specified question. Note that this will check that
# the flag has not already been set before setting it.
#
# @param questionid The ID of the question to flag.
# @param userid     The ID of the user setting the flag.
# @return true on success, undef on error.
sub flag_question {
    my $self       = shift;
    my $questionid = shift;
    my $userid     = shift;

    return $self -> self_error("Question is already flagged")
        if($self -> _is_flagged($questionid, "question"));

    return $self _set_flagged($questionid, "question", $userid);
}


## @method $ unflag_question($questionid)
# Clear the flagged status on the specified question. Note that this will check that
# the flag has been set before clearing it.
#
# @param questionid The ID of the question to unflag.
# @param userid     The ID of the user clearing the flag.
# @return true on success, undef on error.
sub unflag_question {
    my $self       = shift;
    my $questionid = shift;
    my $userid     = shift;

    return $self -> self_error("Question is not flagged")
        unless($self -> _is_flagged($questionid, "question"));

    return $self _set_flagged($questionid, "question", undef);
}


## @method $ create_answer($questionid, $userid, $message)
# Create a new answer using the values provided. This will create a new answer
# in the specified question's thread.
#
# @param questionid The ID of the question this is an answer to.
# @param userid   The ID of the user creating the answer.
# @param message  The message to show in the answer body.
# @return True on success, undef on error.
sub create_answer {
    my $self       = shift;
    my $questionid = shift;
    my $userid     = shift;
    my $message    = shift;

    $self -> clear_error();

    # Get the ID of the question metadata context, so it can be used to make a new
    # context for the answer
    my $parentid = $self -> _get_question_metadataid($questionid)
        or return $self -> self_error("Unable to obtain course metadata id: ".$self -> {"courses"} -> {"errstr"} || "Course does not exist");

    my $metadataid = $self -> {"metadata"} -> create($parentid)
        or return $self -> self_error("Unable to create new metadata context: ".$self -> {"metadata"} -> {"errstr"});

    my $now = time();

    # Make a new answer, with no postid
    my $aid = $self -> _new_answer($metadataid, $questionid, $userid, $now)
        or return undef;

    # Set the answer text.
    return $self -> edit_answer($aid, $userid, $message, $now);
}


## @method $ edit_answer($questionid, $userid, $message)
# Create a new text and attach it to an existing answer, replacing the old
# text for that entry.
#
# @param answerid The ID of the question to attach a new text to.
# @param userid   The ID of the user creating the new text.
# @param message  The message to show in the text body.
# @return True on success, undef on error.
sub edit_question {
    my $self     = shift;
    my $answerid = shift;
    my $userid   = shift;
    my $message  = shift;

    $self -> clear_error();

    my $previd = $self -> _get_current_textid($answerid, "answer");
    return undef unless(defined($previd));

    # Make a new text entry
    my $textid = $self -> _new_text($userid, "", $message, $previd)
        or return undef;

    # Update the answer text id
    return $self -> _set_current_textid($answerid, "answer", $textid);
}


## @method $ delete_answer($answerid, $userid)
# Mark the specified answer as deleted. Note that this will not actually delete
# the answer, simply mark it as deleted so it won't show up in normal listings.
#
# @param answerid The id of the answer to mark as deleted.
# @param userid   The ID of the user deleting the answer.
# @param true on success, undef on error.
sub delete_answer {
    my $self     = shift;
    my $answerid = shift;
    my $userid   = shift;

    return $self -> _delete($answerid, "answer", $userid);
}


## @method $ flag_answer($answerid, $userid)
# Set the flagged status on the specified answer. Note that this will check that
# the flag has not already been set before setting it.
#
# @param answerid The ID of the answer to flag.
# @param userid   The ID of the user setting the flag.
# @return true on success, undef on error.
sub flag_answer {
    my $self     = shift;
    my $answerid = shift;
    my $userid   = shift;

    return $self -> self_error("Answer is already flagged")
        if($self -> _is_flagged($answerid, "answer"));

    return $self _set_flagged($answerid, "answer", $userid);
}


## @method $ unflag_answer($answerid)
# Clear the flagged status on the specified answer. Note that this will check that
# the flag has been set before clearing it.
#
# @param answerid The ID of the answer to unflag.
# @param userid   The ID of the user clearing the flag.
# @return true on success, undef on error.
sub unflag_answer {
    my $self     = shift;
    my $answerid = shift;
    my $userid   = shift;

    return $self -> self_error("Answer is not flagged")
        unless($self -> _is_flagged($answerid, "answer"));

    return $self _set_flagged($answerid, "answer", undef);
}


## @method $ create_comment($id, $type, $userid, $message)
# Create a new comment using the values provided. This will create a new comment
# and attach it to either a question or an answer.
#
# @param id      The ID of the question or answer this is a comment on.
# @param type    The type of entry to attach the comment to, must be "answer" or "question".
# @param userid  The ID of the user creating the comment.
# @param message The message to show in the comment body.
# @return True on success, undef on error.
sub create_comment {
    my $self    = shift;
    my $id      = shift;
    my $type    = shift;
    my $userid  = shift;
    my $message = shift;

    $self -> clear_error();

    my $now = time();

    # Make a new comment, wiht no text
    my $cid = $self -> _new_comment($userid, $now)
        or return undef;

    # Set the answer text.
    $self -> edit_comment($cid, $userid, $message, $now)
        or return undef;

    # Attach it
    $self -> _attach_comment($id, $type, $cid);
}


## @method $ edit_comment($commentid, $userid, $message)
# Create a new text and attach it to an existing comment, replacing the old
# text for that entry.
#
# @param commentid The ID of the comment to attach a new text to.
# @param userid    The ID of the user creating the new text.
# @param message   The message to show in the text body.
# @return True on success, undef on error.
sub edit_comment {
    my $self      = shift;
    my $commentid = shift;
    my $userid    = shift;
    my $message   = shift;

    $self -> clear_error();

    my $previd = $self -> _get_current_textid($commentid, "comment");
    return undef unless(defined($previd));

    # Make a new text entry
    my $textid = $self -> _new_text($userid, "", $message, $previd)
        or return undef;

    # Update the comment text id
    return $self -> _set_current_textid($commentid, "comment", $textid);
}


## @method $ delete_comment($commentid, $userid)
# Mark the specified comment as deleted. Note that this will not actually delete
# the comment, simply mark it as deleted so it won't show up in normal listings.
# Also note that this will keep the comment attached to the question or answer it
# was posted on!
#
# @param answerid The id of the answer to mark as deleted.
# @param userid   The ID of the user deleting the answer.
# @param true on success, undef on error.
sub delete_comment {
    my $self      = shift;
    my $commentid = shift;
    my $userid    = shift;

    return $self -> _delete($commentid, "comment", $userid);
}


## @method $ flag_comment($commentid, $userid)
# Set the flagged status on the specified comment. Note that this will check that
# the flag has not already been set before setting it.
#
# @param commentid The ID of the comment to flag.
# @param userid    The ID of the user setting the flag.
# @return true on success, undef on error.
sub flag_comment {
    my $self      = shift;
    my $commentid = shift;
    my $userid    = shift;

    return $self -> self_error("Comment is already flagged")
        if($self -> _is_flagged($commentid, "comment"));

    return $self _set_flagged($commentid, "comment", $userid);
}


## @method $ unflag_comment($commentid)
# Clear the flagged status on the specified comment. Note that this will check that
# the flag has been set before clearing it.
#
# @param commentid The ID of the comment to unflag.
# @param userid    The ID of the user clearing the flag.
# @return true on success, undef on error.
sub unflag_comment {
    my $self      = shift;
    my $commentid = shift;
    my $userid    = shift;

    return $self -> self_error("Comment is not flagged")
        unless($self -> _is_flagged($commentid, "comment"));

    return $self _set_flagged($commentid, "comment", undef);
}


# ============================================================================
#  Internals

## @method $ _new_question($metadataid, $courseid, $userid, $timestamp)
# Create a new entry in the Feature::qaforums_questions table to act as the 'header' for a
# question.
#
# @param metadataid The ID of the metadata context to associate with the question.
# @param courseid   The ID of the course the question is being posted in.
# @param userid     The ID of the user creating the question.
# @param timestamp  Optional unix typestamp to set for the question. If not provided,
#                   the current time is used.
# @return The new question id on success, undef on error.
sub _new_question {
    my $self       = shift;
    my $metadataid = shift;
    my $courseid   = shift;
    my $userid     = shift;
    my $timestamp  = shift || time();

    $self -> clear_error();

    # Query to create a new question header
    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_questions"}."`
                                            (metadata_id, course_id, created, creator_id)
                                            VALUES(?, ?, ?, ?)");
    my $result = $newh -> execute($metadataid, $courseid, $timestamp, $userid);
    return $self -> self_error("Unable to perform question insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Question insert failed, no rows inserted") if($result eq "0E0");

    # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
    #        Try to find a decent solution for this mess...
    my $qid = $self -> {"dbh"} -> {"mysql_insertid"}
        or return $self -> self_error("Unable to obtain new question row id");

    # Attach to the metadata context
    $self -> {"metadata"} -> attach($metadataid)
        or return $self -> self_error("Error in metadata system: ".$self -> {"metadata"} -> {"errstr"});

    return $qid;
}


## @method $ _new_answer($metadataid, $questionid, $userid, $timestamp)
# Create a new entry in the Feature::qaforums_answers table to act as the 'header' for a
# question.
#
# @param metadataid The ID of the metadata context to associate with the answer.
# @param questionid The ID of the question the answer is being posted in answer to.
# @param userid     The ID of the user creating the answer.
# @param timestamp  Optional unix typestamp to set for the answer. If not provided,
#                   the current time is used.
# @return The new answer id on success, undef on error.
sub _new_answer {
    my $self       = shift;
    my $metadataid = shift;
    my $questionid = shift;
    my $userid     = shift;
    my $timestamp  = shift || time();

    $self -> clear_error();

    # Query to create a new answer header
    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_answers"}."`
                                            (metadata_id, question_id, created, creator_id)
                                            VALUES(?, ?, ?, ?)");
    my $result = $newh -> execute($metadataid, $questionid, $timestamp, $userid);
    return $self -> self_error("Unable to perform answer insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Answer insert failed, no rows inserted") if($result eq "0E0");

    # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
    #        Try to find a decent solution for this mess...
    my $aid = $self -> {"dbh"} -> {"mysql_insertid"}
        or return $self -> self_error("Unable to obtain new answer row id");

    # Attach to the metadata context
    $self -> {"metadata"} -> attach($metadataid)
        or return $self -> self_error("Error in metadata system: ".$self -> {"metadata"} -> {"errstr"});

    return $aid;
}


## @method $ _new_comment($userid, $timestamp)
# Create a new entry in the Feature::qaforums_comments table to act as the 'header' for a
# comment.
#
# @param userid     The ID of the user creating the comment.
# @param timestamp  Optional unix typestamp to set for the comment. If not provided,
#                   the current time is used.
# @return The new comment id on success, undef on error.
sub _new_comment {
    my $self       = shift;
    my $userid     = shift;
    my $timestamp  = shift || time();

    $self -> clear_error();

    # Query to create a new comment header
    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_comments"}."`
                                            (created, creator_id)
                                            VALUES(?, ?)");
    my $result = $newh -> execute($timestamp, $userid);
    return $self -> self_error("Unable to perform comment insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Comment insert failed, no rows inserted") if($result eq "0E0");

    # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
    #        Try to find a decent solution for this mess...
    my $cid = $self -> {"dbh"} -> {"mysql_insertid"}
        or return $self -> self_error("Unable to obtain new comment row id");

    return $cid;
}


## @method $ _delete($id, $type, $userid)
# Mark the specified question, answer, or comment as deleted, and record who deleted it
# and when.
#
# @param id     The ID of the question, answer, or comment to delete
# @param type   The type of entry to delete, should be "question", "answer"
#               or "comment"
# @param userid The ID of the user doing the delete.
# @return true on success, undef on error.
sub _delete {
    my $self   = shift;
    my $id     = shift;
    my $type   = shift;
    my $userid = shift;

    my $delh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s"}."`
                                            SET deleted = UNIX_TIMESTAMP(), deleted_id = ?
                                            WHERE id = ?");
    my $result = $delh -> execute($userid, $id);
    return $self -> self_error("Unable to perform $type delete: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("$type delete failed, no rows updated") if($result eq "0E0");

    return 1;
}


## @method $ _new_text($userid, $subject, $message, $timestamp, $previd)
# Create a new text entry, recording whether it is an edit of a previous entry
# or a new one.
#
# @param userid    The ID of the user posting the text.
# @param subject   The text subject (may be undef)
# @param message   The message to show in the text body.
# @param timestamp Optional unix typestamp to set for the text. If not provided,
#                  the current time is used.
# @param previd    The ID of the previous text entry, zero or undef if there is
#                  no previous.
# @return The ID of the new text on success, undef on error.
sub _new_text {
    my $self      = shift;
    my $userid    = shift;
    my $subject   = shift;
    my $message   = shift;
    my $timestamp = shift || time();
    my $previd    = shift;

    $self -> clear_error();

    # Zero previd makes no sense, so undef it
    undef $previd if(!$previd);

    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_texts"}."`
                                            (edited, editor_id, previous_id, subject, message)
                                            VALUES(?, ?, ?, ?, ?)");

    my $result = $newh -> execute($timestamp, $userid, $previd, $subject, $message);
    return $self -> self_error("Unable to perform text insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Text insert failed, no rows inserted") if($result eq "0E0");

    # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
    #        Try to find a decent solution for this mess...
    my $textid = $self -> {"dbh"} -> {"mysql_insertid"}
        or return $self -> self_error("Unable to obtain new text entry row id");

    return $textid;
}


## @method $ _attach_comment($id, $type, $commentid)
# Attach the specified comment to a question or answer.
#
# @param id        The ID of the question or answer to attach the comment to.
# @param type      The type to attach the comment to, must be "question" or "answer"
# @param commentid The ID of the comment to attach
# @return true on success, undef on error
sub _attach_comment {
    my $self      = shift;
    my $id        = shift;
    my $type      = shift;
    my $commentid = shift;

    return $self -> self_error("Illegal type passed to _attach_comment")
        unless($type eq "question" || $type eq "answer");

    my $atth = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s_comments"}."`
                                            (${type}_id, comment_id)
                                            VALUES(?, ?)");
    my $result = $atth -> execute($id, $commentid);
    return $self -> self_error("Unable to perform comment relation insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Comment relation insert failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method $ _get_question_metadataid($questionid)
# Obtain the ID of the metadata context attached to the specified question.
#
# @param questionid The ID of the question to get the context for.
# @return The metadata ID on success, undef on error.
sub _get_question_metadataid {
    my $self       = shift;
    my $questionid = shift;

    $self -> clear_error();

    my $queryh = $self -> {"dbh"} -> prepare("SELECT metadata_id
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_questions"}."`
                                              WHERE id = ?");
    $queryh -> execute($id)
        or return $self -> self_error("Unable to execute question metadata id query: ".$self -> {"dbh"} -> {"errstr"});

    my $row = $queryh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch metadata context for question $id: entry does not exist");

    return $row -> [0]
        or return $self -> self_error("No metadata context set for question $questionid. This should not happen");
}


## @method $ _get_current_textid($id, $type)
# Obtain the ID of the text currently set for the specified question, answer,
# or comment.
#
# @param id   The ID of the question, answer, or comment to get the text ID for.
# @param type The type of entry to look for, should be "question", "answer"
#             or "comment"
# @return The text ID on success, 0 if the entry has no text ID set, undef
#         on error.
sub _get_current_textid {
    my $self = shift;
    my $id   = shift;
    my $type = shift;

    $self -> clear_error();

    # Check the type is valid for safety
    return $self -> self_error("Illegal type specified in call to _get_current_textid")
        unless($type eq "question" || $type eq "answer" || $type eq "comment");

    my $queryh = $self -> {"dbh"} -> prepare("SELECT text_id
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s"}."`
                                              WHERE id = ?");
    $queryh -> execute($id)
        or return $self -> self_error("Unable to execute $type text id query: ".$self -> {"dbh"} -> {"errstr"});

    my $row = $queryh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch text id for $type $id: entry does not exist");

    return $row -> [0] || 0;
}


## @method $ _set_current_textid($id, $type, $textid)
# Set the ID of the current text for the specified question, answer, or comment.
#
# @param id     The ID of the question entry to set the text ID for.
# @param type   The type of entry to look for, should be "question", "answer"
#               or "comment"
# @param textid The ID of the text to set as the current text.
# @return True on success, undef on error
sub _set_current_textid {
    my $self   = shift;
    my $id     = shift;
    my $type   = shift;
    my $textid = shift;

    $self -> clear_error();

    # Check the type is valid for safety
    return $self -> self_error("Illegal type specified in call to _set_current_textid")
        unless($type eq "question" || $type eq "answer" || $type eq "comment");

    my $seth = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s"}."`
                                            SET text_id = ?
                                            WHERE id = ?");
    my $result = $seth -> execute($textid, $id);
    return $self -> self_error("Unable to perform $type text update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("$type text update failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method $ _is_flagged($id, $type)
# Determine whether the specified question, answer, or comment has been flagged,
# and if it has return the ID of the user who flagged it.
#
# @param id   The ID of the question, answer, or comment to check
# @param type The type of entry to check, must be "question", "answer", or "comment"
# @return The ID of the user who flagged the entry if it is flagged, 0 if it is not,
#         undef on error.
sub _is_flagged {
    my $self = shift;
    my $id   = shift;
    my $type = shift;

    # Check the entry
    my $checkh = $self -> {"dbh"} -> prepare("SELECT flagged_id
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s"}."`
                                              WHERE id = ?");
    $checkh -> execute($id)
        or return $self -> self_error("Unable to execute $type flagged query: ".$self -> {"dbh"} -> {"errstr"});

    my $row = $checkh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch flagged status $type $id: entry does not exist");

    return $row -> [0] || 0;
}


## @method $ _set_flagged($id, $type, $user)
# Set or clear the flagged status of the specified entry.
#
# @param id    The ID of the question, answer, or comment to alter the flagged status of
# @param type  The type of entry to check, must be "question", "answer", or "comment"
# @param user  The user setting the flagged status, if this is undef the flagged status
#              is cleared.
# @return True on success, undef on error
sub _set_flagged {
    my $self = shift;
    my $id   = shift;
    my $type = shift;
    my $user = shift;
    my $now;

    $now = time() if($user);

    my $seth = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s"}."`
                                            SET flagged = ?, flagged_id = ?
                                            WHERE id = ?");
    my $result = $seth -> execute($now, $user, $id);
    return $self -> self_error("Unable to perform $type flagged update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("$type flagged update failed, no rows inserted") if($result eq "0E0");

    return 1;
}

1;
