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
use List::Util qw(max);

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
# @return The new question id on success, undef on error.
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
    $self -> edit_question($qid, $userid, $subject, $message, $now)
        or return undef;

    # DO TAGS HERE

    return $qid;
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

    my $previd = $self -> _get_current_textid($questionid, "question");
    return undef unless(defined($previd));

    # Make a new text entry
    my $textid = $self -> _new_text($userid, $subject, $message, $previd)
        or return undef;

    # Update the question textid
    $self -> _set_current_textid($questionid, "question", $textid)
        or return undef;

    return $self -> _sync_counts($questionid);
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

    $self -> clear_error();

    return $self -> self_error("Question is already flagged")
        if($self -> _is_flagged($questionid, "question"));

    return $self -> _set_flagged($questionid, "question", $userid);
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

    $self -> clear_error();

    return $self -> self_error("Question is not flagged")
        unless($self -> _is_flagged($questionid, "question"));

    return $self -> _set_flagged($questionid, "question", undef);
}


## @method $ rate_question($questionid, $userid, $direction)
# Update the rating on the specified question.
#
# @param questionid The ID of the question to rate.
# @param userid     The user performing the rating.
# @param direction  The direction to rate the question, must be "up" or "down"
# @return true on success, undef on error.
sub rate_question {
    my $self       = shift;
    my $questionid = shift;
    my $userid     = shift;
    my $direction  = shift;

    return $self -> _rate_entry($questionid, "question", $userid, $direction);
}


## @method $ unrate_question($questionid, $userid)
# Cancel a user's rating on the specified question. This is safe to call
# even if the user has not rated the question.
#
# @param questionid The ID of the question to cancel the rating for.
# @param userid     The user whose rating shold be cancelled.
# @return true on success, undef on error.
sub unrate_question {
    my $self       = shift;
    my $questionid = shift;
    my $userid     = shift;

    return $self -> _unrate_entry($questionid, "question", $userid);
}


## @method $ user_has_rated_question($questionid, $userid)
# Check whether the user has already rated this question.  Note that this
# will not check whether the user has already rated the question - the
# caller should do this using user_has_rated_question() before calling this.
#
# @param questionid The ID of the question to check the rating history on.
# @param userid     The ID of the user to check for rating operations.
# @return "up" or "down" if the user has rated the question, "" otherwise,
#         undef on error.
sub user_has_rated_question {
    my $self       = shift;
    my $questionid = shift;
    my $userid     = shift;

    my $rating = $self -> _user_has_rated($questionid, "question", $userid)
        or return undef;

    return $rating -> {"updown"} || "";
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
    $self -> edit_answer($aid, $userid, $message, $now)
        or return undef;

    return $self -> _sync_counts($questionid);
}


## @method $ edit_answer($questionid, $userid, $message)
# Create a new text and attach it to an existing answer, replacing the old
# text for that entry.
#
# @param answerid The ID of the question to attach a new text to.
# @param userid   The ID of the user creating the new text.
# @param message  The message to show in the text body.
# @return True on success, undef on error.
sub edit_answer {
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
    $self -> _set_current_textid($answerid, "answer", $textid)
        or return undef;

    my $qid = $self -> _get_answer_questionid($answerid, "answer")
        or return undef;

    return $self -> _sync_counts($qid);
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

    $self -> _delete($answerid, "answer", $userid)
        or return undef;

    my $qid = $self -> _get_answer_questionid($answerid, "answer")
        or return undef;

    return $self -> _sync_counts($qid);
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

    $self -> clear_error();

    return $self -> self_error("Answer is already flagged")
        if($self -> _is_flagged($answerid, "answer"));

    return $self -> _set_flagged($answerid, "answer", $userid);
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

    $self -> clear_error();

    return $self -> self_error("Answer is not flagged")
        unless($self -> _is_flagged($answerid, "answer"));

    return $self -> _set_flagged($answerid, "answer", undef);
}


## @method $ rate_answer($answerid, $userid, $direction)
# Update the rating on the specified answer. Note that this will not check
# whether the user has already rated the answer - the caller should do this
# using user_has_rated_answer() before calling this.
#
# @param answerid  The ID of the answer to rate.
# @param userid    The user performing the rating.
# @param direction The direction to rate the answer, must be "up" or "down"
# @return true on success, undef on error.
sub rate_answer {
    my $self      = shift;
    my $answerid  = shift;
    my $userid    = shift;
    my $direction = shift;

    return $self -> _rate_entry($answerid, "answer", $userid, $direction);
}


## @method $ unrate_answer($answerid, $userid)
# Cancel a user's rating on the specified answer. This is safe to call
# even if the user has not rated the answer.
#
# @param answerid The ID of the answer to cancel the rating for.
# @param userid   The user whose rating shold be cancelled.
# @return true on success, undef on error.
sub unrate_answer {
    my $self      = shift;
    my $answerid  = shift;
    my $userid    = shift;

    return $self -> _unrate_entry($answerid, "answer", $userid);
}


## @method $ user_has_rated_answer($answerid, $userid)
# Check whether the user has already rated this answer.
#
# @param answerid The ID of the answer to check the rating history on.
# @param userid   The ID of the user to check for rating operations.
# @return true if the user has rated the answer, false otherwise,
#         undef on error.
sub user_has_rated_answer {
    my $self     = shift;
    my $answerid = shift;
    my $userid   = shift;

    my $rating = $self -> _user_has_rated($answerid, "answer", $userid)
        or return undef;

    return $rating -> {"rated"} || 0;
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
    $self -> _attach_comment($id, $type, $cid)
        or return undef;

    my $qid = $self -> _get_comment_questionid($cid)
        or return undef;

    return $self -> _sync_counts($qid);
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

    my $previd = $self -> _get_current_textid($commentid, "comment");
    return undef unless(defined($previd));

    # Make a new text entry
    my $textid = $self -> _new_text($userid, "", $message, $previd)
        or return undef;

    # Update the comment text id
    $self -> _set_current_textid($commentid, "comment", $textid)
        or return undef;

    my $qid = $self -> _get_comment_questionid($commentid)
        or return undef;

    return $self -> _sync_counts($qid);
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

    $self -> _delete($commentid, "comment", $userid)
        or return undef;

    my $qid = $self -> _get_comment_questionid($commentid)
        or return undef;

    return $self -> _sync_counts($qid);
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

    $self -> clear_error();

    return $self -> self_error("Comment is already flagged")
        if($self -> _is_flagged($commentid, "comment"));

    return $self -> _set_flagged($commentid, "comment", $userid);
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

    $self -> clear_error();

    return $self -> self_error("Comment is not flagged")
        unless($self -> _is_flagged($commentid, "comment"));

    return $self -> _set_flagged($commentid, "comment", undef);
}


## @method $ comment_is_helpful($commentid, $userid)
# Update the 'helpful' counter for the specified comment. This will not check whether
# the user has already marked the comment as helpful - the caller should do this
# using user_marked_helpful() before calling this
#
# @param commentid The ID of the comment deemed helpful by the user.
# @param userid    The ID of the user marking the comment.
# @return true on success, undef otherwise.
sub comment_is_helpful {
    my $self      = shift;
    my $commentid = shift;
    my $userid    = shift;

    return $self -> _mark_as_helpful($commentid, $userid);
}


## @method $ cancel_is_helpful($commentid, $userid)
# The user has decided the comment isn't helpful, so cancel a previous 'is helpful'
# mark by the user.
#
# @param commentid The ID of the comment the user has decided isn't helpful after all.
# @param userid    The ID of the user who can't make up their mind.
# @return true on success (or no action needed), undef otherwise.
sub cancel_is_helpful {
    my $self      = shift;
    my $commentid = shift;
    my $userid    = shift;

    return $self -> _undo_as_helpful($commentid, $userid);
}


## @method $ user_marked_helpful($commentid, $userid)
# Determine whether the user has marked the comment as helpful. If the user
# has marked the comment as helpful, and has not yet cancelled that mark,
# this will return true.
#
# @param commentid The ID of the comment to check for helpfulness to the user.
# @param userid    The ID of the user who may or may not find the comment helpful.
# @return true if the user has marked the comment as helpful, false otherwise,
#         and undef on error.
sub user_marked_helpful {
    my $self      = shift;
    my $commentid = shift;
    my $userid    = shift;

    my $rating = $self -> _user_recorded_helpful($commentid, $userid)
        or return undef;

    return $rating -> {"marked"} || 0;
}


# ============================================================================
#  Listing and extraction

## @method $ get_question_count($courseid, $noanswer)
# Determine how many questions are available in the category the user has selected.
# This will count how many questions have been asked in the current course, potentially
# filtering the list so that only unanswered questions are counted.
#
# @param courseid The ID of the course to check for qaforum questions
# @param noanswer If true, this will only count questions with no answers, otherwise
#                 all questions (with or without answers) are counted.
# @return The number of questions on success (*which may be zero*), or undef on error.
sub get_question_count {
    my $self     = shift;
    my $courseid = shift;
    my $noanswer = shift;

    my $counth = $self -> {"dbh"} -> prepare("SELECT COUNT(*)
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_questions"}."`
                                              WHERE course_id = ?
                                              AND deleted IS NULL".
                                             ($noanswer ? "AND answers = 0 " : ""));
    $counth -> execute($courseid)
        or return $self -> self_error("Unable to execute question count query: ".$self -> {"dbh"} -> errstr);

    my $count = $counth -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch question count data. This should not happen");

    return $count -> [0];
}


## @method $ get_question_list($courseid, $settings)
# Generate an array of questions set in the current course, sorted by the specified
# mode. The settings argument determines, primarily, the order entries are returned in,
# and any filtering and limiting that may be needed. The following settings are
# understood by the function:
#
# - `mode`     - determines what controls the sort order. Should be either "created",
#                "updated", or "rating". If not specified, this defaults to "created".
# - `ordering" - controls whether newer/higher rated entries appear first or last.
#                Should be "highfirst" for newer/higher rated, or "lowfirst" for older/
#                lower rated. If not set, defaults to "highfirst".
# - `noanswer` - if true, only questions with no answers are returned. Default is false.
# - `offset`   - Offset from the start of the results to return. Defaults to 0.
# - `count`    - The number of entries to return. If not set, all entries are returned.
#                Note that, if the count is not set, the offset will be ignored.
#
# @param courseid The ID of the course to fetch questions from
# @param settings A reference to a hash of settings to control the listing.
# @return A reference to an array containing question data on success, undef on error.
sub get_question_list {
    my $self     = shift;
    my $courseid = shift;
    my $settings = shift || {};

    # Check the configuration values are sane
    $settings -> {"mode"} = "created"
        unless(defined($settings -> {"mode"}) && ($settings -> {"mode"} eq "updated" || $settings -> {"mode"} eq "rating"));

    $settings -> {"ordering"} = "highfirst"
        unless(defined($settings -> {"ordering"}) && $settings -> {"ordering"} eq "lowfirst");

    $settings -> {"count"} = undef
        unless(defined($settings -> {"count"}) && $settings -> {"count"} =~ /^\d+$/);

    $settings -> {"offset"} = undef
        unless(defined($settings -> {"count"}) && defined($settings -> {"offset"}) && $settings -> {"offset"} =~ /^\d+$/);

    my @limit;
    push(@limit, $settings -> {"offset"}) if($settings -> {"offset"});
    push(@limit, $settings -> {"count"})  if($settings -> {"count"});

    # fetch the rows...
    my $query = "SELECT q.*, t.edited, t.editor_id, t.subject, t.message
                 FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_questions"}."` AS q,
                      `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_texts"}."` AS t
                 WHERE q.course_id = ?
                 AND q.deleted IS NULL
                 AND t.id = q.text_id ".
                ($settings -> {"noanswer"} ? "AND q.answers = 0 " : "").
                "ORDER BY ".$settings -> {"mode"}." ".
               ($settings -> {"ordering"} eq "highfirst" ? "DESC " : "ASC ");

    $query .= "LIMIT ".join(",", @limit) if(scalar(@limit));

    my $qlisth = $self -> {"dbh"} -> prepare($query);

    $qlisth -> execute($courseid)
        or return $self -> self_error("Unable to execute question list query: ".$self -> {"dbh"} -> errstr);

    # fetchall should do everything needed here...
    return $qlisth -> fetchall_arrayref({});
}


## @method $ get_question($questionid)
# Obtain the data for the specified question. This returns the question data, if avaulable,
# including the latest revision text. Note that it does not include any answers, or comment
# and those need to be fetched separately with get_comments() and get_answers().
#
# @param courseid   The ID of the course the question is in. This is not strictly needed
#                   for lookup, but is used to enfore access control.
# @param questionid The ID of the question to get the data for.
# @return A reference to a hash containing the question data on success, undef on error.
sub get_question {
    my $self       = shift;
    my $courseid   = shift;
    my $questionid = shift;

    my $geth = $self -> {"dbh"} -> prepare("SELECT q.*, t.edited, t.editor_id, t.subject, t.message
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_questions"}."` AS q,
                                                 `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_texts"}."` AS t
                                            WHERE q.course_id = ?
                                            AND q.id = ?
                                            AND q.deleted IS NULL
                                            AND t.id = q.text_id");
    $geth -> execute($courseid, $questionid)
        or return $self -> self_error("Unable to execute question query: ".$self -> {"dbh"} -> errstr);

    return $geth -> fetchrow_hashref();
}


## @method $ get_comments($id, $type)
# FEtch all the comments attached to the specified answer or question.
#
# @param id   The ID of the question or answer to fetch the comments for.
# @param type The type of entry to fetch the comments for, must be "question" or "answer".
# @return A reference to an array of hashrefs containing the comment data on success
#         (note: if there are no comments, this will be an empty array!), undef on error.
sub get_comments {
    my $self = shift;
    my $id   = shift;
    my $type = shift;

    my $commh = $self -> {"dbh"} -> prepare("SELECT c.*, t.message, t.editor_id, t.edited
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s_comments"}."` AS r,
                                                  `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_comments"}."` AS c,
                                                  `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_texts"}."` AS t
                                             WHERE r.${type}_id = ?
                                             AND c.id = r.comment_id
                                             AND c.deleted IS NULL
                                             AND t.id = c.text_id
                                             ORDER BY c.created");
    $commh -> execute($id)
        or return $self -> self_error("Unable to execute comment query: ".$self -> {"dbh"} -> errstr);

    return $commh -> fetchall_arrayref({});
}


# ============================================================================
#  Internals

## @method private $ _new_question($metadataid, $courseid, $userid, $timestamp)
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
                                            (metadata_id, course_id, created, creator_id, updated)
                                            VALUES(?, ?, ?, ?, ?)");
    my $result = $newh -> execute($metadataid, $courseid, $timestamp, $userid, $timestamp);
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


## @method private $ _new_answer($metadataid, $questionid, $userid, $timestamp)
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
                                            (metadata_id, question_id, created, creator_id, updated)
                                            VALUES(?, ?, ?, ?, ?)");
    my $result = $newh -> execute($metadataid, $questionid, $timestamp, $userid, $timestamp);
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


## @method private $ _new_comment($userid, $timestamp)
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
                                            (created, creator_id, updated)
                                            VALUES(?, ?, ?)");
    my $result = $newh -> execute($timestamp, $userid, $timestamp);
    return $self -> self_error("Unable to perform comment insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Comment insert failed, no rows inserted") if($result eq "0E0");

    # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
    #        Try to find a decent solution for this mess...
    my $cid = $self -> {"dbh"} -> {"mysql_insertid"}
        or return $self -> self_error("Unable to obtain new comment row id");

    return $cid;
}


## @method private $ _delete($id, $type, $userid)
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

    $self -> clear_error();

    my $delh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s"}."`
                                            SET deleted = UNIX_TIMESTAMP(), deleted_id = ?, updated = UNIX_TIMESTAMP()
                                            WHERE id = ?");
    my $result = $delh -> execute($userid, $id);
    return $self -> self_error("Unable to perform $type delete: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("$type delete failed, no rows updated") if($result eq "0E0");

    return 1;
}


## @method private $ _new_text($userid, $subject, $message, $timestamp, $previd)
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


## @method private $ _attach_comment($id, $type, $commentid)
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

    $self -> clear_error();

    # Force a legal type
    $type = "question" unless(defined($type) && $type eq "answer");

    my $atth = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s_comments"}."`
                                            (${type}_id, comment_id)
                                            VALUES(?, ?)");
    my $result = $atth -> execute($id, $commentid);
    return $self -> self_error("Unable to perform comment relation insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Comment relation insert failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method private $ _get_question_metadataid($questionid)
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
    $queryh -> execute($questionid)
        or return $self -> self_error("Unable to execute question metadata id query: ".$self -> {"dbh"} -> {"errstr"});

    my $row = $queryh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch metadata context for question $questionid: entry does not exist");

    return $row -> [0]
        or return $self -> self_error("No metadata context set for question $questionid. This should not happen");
}


## @method private $ _get_answer_questionid($answerid)
# Obtain the ID of the question this answer is attached to.
#
# @param answerid The ID of the answer to fetch the question id for.
# @return The question ID on success, undef on error.
sub _get_answer_questionid {
    my $self     = shift;
    my $answerid = shift;

    $self -> clear_error();

    my $queryh = $self -> {"dbh"} -> prepare("SELECT question_id
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_answers"}."`
                                              WHERE id = ?");
    $queryh -> execute($answerid)
        or return $self -> self_error("Unable to execute answer question id query: ".$self -> {"dbh"} -> {"errstr"});

    my $row = $queryh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch question id for answer $answerid: entry does not exist");

    return $row -> [0]
        or return $self -> self_error("No question id set for answer $answerid. This should not happen");
}


## @method private $ _get_comment_questionid($commentid)
# Obtain the ID of the question this comment is attached to, either directly
# por via a question.
#
# @param commentid The ID of the comment to fetch the question ID for.
# @return The question ID on success, undef on error.
sub _get_comment_questionid {
    my $self      = shift;
    my $commentid = shift;

    # First check for the commentid in the question/comment relation table, that's
    # the simple case...
    my $questh = $self -> {"dbh"} -> prepare("SELECT question_id
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_questions_comments"}."`
                                              WHERE comment_id = ?");
    $questh -> execute($commentid)
        or return $self -> self_error("Unable to execute question/comment lookup: ".$self -> {"dbh"} -> errstr);

    # If this returns a row, the comment is attached to a question, so life is easy
    my $quest = $questh -> fetchrow_arrayref();
    return $quest -> [0] if($quest);

    # Comment is not on a question, must be on an answer (we hope...)
    my $ansh = $self -> {"dbh"} -> prepare("SELECT answer_id
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_answers_comments"}."`
                                            WHERE comment_id = ?");
    $ansh -> execute($commentid)
        or return $self -> self_error("Unable to execute answer/comment lookup: ".$self -> {"dbh"} -> errstr);

    # If the comment is set on an answer, get its question id
    my $answer = $ansh -> fetchrow_arrayref();
    return $self -> _get_answer_questionid($answer -> [0]) if($answer);

    # Get here and the comment doesn't seem to be attached to anything, panic.
    return $self -> self_error("Comment $commentid does not appear to be attached to anything!");
}


## @method private $ _get_current_textid($id, $type)
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

    # Force a legal type
    $type = "question" unless(defined($type) && ($type eq "answer" || $type eq "comment"));

    my $queryh = $self -> {"dbh"} -> prepare("SELECT text_id
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s"}."`
                                              WHERE id = ?");
    $queryh -> execute($id)
        or return $self -> self_error("Unable to execute $type text id query: ".$self -> {"dbh"} -> {"errstr"});

    my $row = $queryh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch text id for $type $id: entry does not exist");

    return $row -> [0] || 0;
}


## @method private $ _set_current_textid($id, $type, $textid)
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

    # Force a legal type
    $type = "question" unless(defined($type) && ($type eq "answer" || $type eq "comment"));

    my $seth = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s"}."`
                                            SET text_id = ?, updated = UNIX_TIMESTAMP()
                                            WHERE id = ?");
    my $result = $seth -> execute($textid, $id);
    return $self -> self_error("Unable to perform $type text update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("$type text update failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method private $ _view_question($questionid)
# Increment the view counter for the specified question.
#
# @param questionid The ID of the question to update the view counter for
# @return true on success, undef otherwise.
sub _view_question {
    my $self       = shift;
    my $questionid = shift;

    my $seth = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_questionss"}."`
                                            SET viewed = UNIX_TIMESTAMP(), views = views + 1
                                            WHERE id = ?");
    my $result = $seth -> execute($questionid);
    return $self -> self_error("Unable to perform view count update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("View count update failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method private $ _is_flagged($id, $type)
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

    $self -> clear_error();

    # Force a legal type
    $type = "question" unless(defined($type) && $type eq "answer");

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


## @method private $ _set_flagged($id, $type, $user)
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

    $self -> clear_error();

    # Force a legal type
    $type = "question" unless(defined($type) && $type eq "answer");

    $now = time() if($user);

    my $seth = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s"}."`
                                            SET flagged = ?, flagged_id = ?, updated = UNIX_TIMESTAMP()
                                            WHERE id = ?");
    my $result = $seth -> execute($now, $user, $id);
    return $self -> self_error("Unable to perform $type flagged update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("$type flagged update failed, no rows updated") if($result eq "0E0");

    return 1;
}


## @method private $ _rate_entry($id, $type, $userid, $mode)
# Update the rating of a question or answer. This creates a new rating history entry
# in the ratings table, and then attaches it to a question or answer according to the
# specified type. Note that this does not check whether the user has already rated the
# question or answer first - the caller should check this with _user_has_rated() before
# calling this.
#
# @param id     The ID of the question or answer to change the rating of.
# @param type   The type of entry to rate, must be "question" or "answer".
# @param userid The ID of the user performing the rating operation.
# @param mode   The rating change, must be "up" or "down".
# @return true on success, undef on error.
sub _rate_entry {
    my $self   = shift;
    my $id     = shift;
    my $type   = shift;
    my $userid = shift;
    my $mode   = shift;

    $self -> clear_error();

    # Force a legal type and mode
    $type = "question" unless(defined($type) && $type eq "answer");
    $mode = "down"     unless(defined($mode) && $mode eq "up");

    # Do a hopefully near-atomic update to the rating on the question/answer
    my $tickh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s"}."`
                                             SET updated = UNIX_TIMESTAMP(), rating = rating ".($mode eq "up" ? "+" : "-")." 1
                                             WHERE id = ?");
    my $result = $tickh -> execute($id);
    return $self -> self_error("Unable to perform $type rating update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("$type rating update failed, no rows updated") if($result eq "0E0");

    # Now get the new rating
    my $rateh = $self -> {"dbh"} -> prepare("SELECT rating
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s"}."`
                                             WHERE id = ?");
    $rateh -> execute($id)
        or return $self -> self_error("Unable to execute $type rating query: ".$self -> {"dbh"} -> errstr);

    # The or on this should never actually happen - the update above should fail first, but check anyway.
    my $rate = $rateh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch $type rating: entry does not exist?");

    # Now create a new rating history entry
    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_ratings"}."`
                                            (rated, rater_id, updown, rating)
                                            VALUES(UNIX_TIMESTAMP(), ?, ?, ?)");
    $result = $newh -> execute($userid, $mode, $rate -> [0]);
    return $self -> self_error("Unable to perform rating history insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Rating history insert failed, no rows inserted") if($result eq "0E0");

    my $ratingid = $self -> {"dbh"} -> {"mysql_insertid"}
        or return $self -> self_error("Unable to obtain new rating history entry row id");

    # Now it needs to be attached to the question/answer
    my $attach = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s_ratings"}."`
                                            (${type}_id, rating_id)
                                            VALUES(?, ?)");
    $result = $attach -> execute($id, $ratingid);
    return $self -> self_error("Unable to perform rating relation insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Rating relation insert failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method private $ _unrate_entry($id, $type, $userid)
# Cancel a user's rating of the specified question or answer, if they have
# rated it. If this user has not rated the entry, this does nothing and
# returns true.
#
# @param id     The ID of the question or answer to change the rating of.
# @param type   The type of entry to rate, must be "question" or "answer".
# @param userid The ID of the user performing the rating operation.
# @return true on success (or no unrating was needed), undef on error.
sub _unrate_entry {
    my $self   = shift;
    my $id     = shift;
    my $type   = shift;
    my $userid = shift;

    $self -> clear_error();

    # Force a legal type
    $type = "question" unless(defined($type) && $type eq "answer");

    # Determine whether the user has rated the entry; this gets the data if they have
    my $rated = $self -> _user_has_rated($id, $type, $userid);
    return undef unless(defined($rated));

    # No rating recorded? Exit with 'success' as unrating is not needed.
    return 1 unless($rated -> {"rated"});

    # Rating happened, undo it
    my $tickh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s"}."`
                                             SET updated = UNIX_TIMESTAMP(), rating = rating ".($rated -> {"updown"} eq "up" ? "-" : "+")." 1
                                             WHERE id = ?");
    my $result = $tickh -> execute($id);
    return $self -> self_error("Unable to perform $type rating update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("$type rating update failed, no rows updated") if($result eq "0E0");

    # Cancel the rating
    my $cancelh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_ratings"}."`
                                               SET cancelled = UNIX_TIMESTAMP()
                                               WHERE id = ?");
    $result = $cancelh -> execute($rated -> {"id"});
    return $self -> self_error("Unable to perform $type rating cancel: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("$type rating cancel failed, no rows updated") if($result eq "0E0");

    return 1;
}


## @method private $ _user_has_rated($id, $type, $userid)
# Determine whether the specified user has rated this question or answer.
#
# @param id     The ID of the question or answer to check the rating history on.
# @param type   The type of entry to check, must be "question" or "answer".
# @param userid The ID of the user to check for rating operations.
# @return A reference to a hash containing the user's rating data for this
#         entry if they have rated the question or answer, an empty hash if
#         they have not, undef on error.
sub _user_has_rated {
    my $self   = shift;
    my $id     = shift;
    my $type   = shift;
    my $userid = shift;

    $self -> clear_error();

    # Force a legal type
    $type = "question" unless(defined($type) && $type eq "answer");

    # Look for uncancelled rating operations
    my $checkh = $self -> {"dbh"} -> prepare("SELECT h.*
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_ratings"}."` AS h,
                                                   `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s_ratings"}."` AS r
                                              WHERE r.${type}_id = ?
                                              AND h.id = r.rating_id
                                              AND h.rater_id = ?
                                              AND h.cancelled IS NULL");
    $checkh -> execute($id, $userid)
        or return $self -> self_error("Unable to execute $type rating lookup for user $userid: ".$self -> {"dbh"} -> errstr);

    my $rated = $checkh -> fetchrow_hashref();

    return $rated ? $rated : {};
}


## @method private $ _mark_as_helpful($commentid, $userid)
# Allow a user to mark a comment as helpful. This increments the comment's 'helpful' counter
# and records the user's action in a history table.
#
# @param commentid The ID of the comment deemed helpful by the user.
# @param userid    The ID of the user marking the comment.
# @return true on success, undef otherwise.
sub _mark_as_helpful {
    my $self      = shift;
    my $commentid = shift;
    my $userid    = shift;

    $self -> clear_error();

    # Do a hopefully near-atomic update to the rating on the question/answer
    my $tickh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_comments"}."`
                                             SET updated = UNIX_TIMESTAMP(), helpful = helpful + 1
                                             WHERE id = ?");
    my $result = $tickh -> execute($commentid);
    return $self -> self_error("Unable to perform comment rating update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Comment rating update failed, no rows updated") if($result eq "0E0");

    # Now get the new rating
    my $rateh = $self -> {"dbh"} -> prepare("SELECT helpful
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_comments"}."`
                                             WHERE id = ?");
    $rateh -> execute($commentid)
        or return $self -> self_error("Unable to execute comment rating query: ".$self -> {"dbh"} -> errstr);

    # The or on this should never actually happen - the update above should fail first, but check anyway.
    my $helpful = $rateh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch comment rating: entry does not exist?");

    # Now create a new history entry
    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_helpfuls"}."`
                                            (comment_id, marked, marked_id, rating)
                                            VALUES(?, UNIX_TIMESTAMP(), ?, ?)");
    $result = $newh -> execute($commentid, $userid, $helpful -> [0]);
    return $self -> self_error("Unable to perform helpful history insert: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Helpful history insert failed, no rows inserted") if($result eq "0E0");

    return 1;
}


## @method private $ _undo_as_helpful($commentid, $userid)
# Cancel the user's assessment of this comment as helpful. This undoes the helpful
# rating made by the user (assuming such a rating has been made). If the user has
# not rated the comment, this does nothing and returns true.
#
# @param commentid The ID of the comment the user has decided isn't helpful after all.
# @param userid    The ID of the user who can't make up their mind.
# @return true on success (or no action needed), undef otherwise.
sub _undo_as_helpful {
    my $self      = shift;
    my $commentid = shift;
    my $userid    = shift;

    $self -> clear_error();

    # Determine whether the user has rated the comment; this gets the data if they have
    my $rated = $self -> _user_recorded_helpful($commentid, $userid);
    return undef unless(defined($rated));

    # No rating recorded? Exit with 'success' as unrating is not needed.
    return 1 unless($rated -> {"marked"});

    # Rating happened, undo it
    my $tickh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_comments"}."`
                                             SET updated = UNIX_TIMESTAMP(), helpful = helpful - 1
                                             WHERE id = ?");
    my $result = $tickh -> execute($commentid);
    return $self -> self_error("Unable to perform coment helpfulness update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Comment helpfullness update failed, no rows updated") if($result eq "0E0");

    # Cancel the helpfulness
    my $cancelh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_helpfuls"}."`
                                               SET cancelled = UNIX_TIMESTAMP()
                                               WHERE id = ?");
    $result = $cancelh -> execute($rated -> {"id"});
    return $self -> self_error("Unable to perform comment rating cancel: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Comment rating cancel failed, no rows updated") if($result eq "0E0");

    return 1;

}


## @method private $ _user_recorded_helpful($commentid, $userid)
# Determine whether the user has marked the comment as helpful. If the user
# has marked the comment as helpful, and has not yet cancelled that mark,
# this will return the data.
#
# @param commentid The ID of the comment to check for helpfulness to the user.
# @param userid    The ID of the user who may or may not find the comment helpful.
# @return A reference to a hash containing the user's helpful data on success,
#         an empty hash if the user has not marked the comment as helpful, or
#         undef on error.
sub _user_recorded_helpful {
    my $self      = shift;
    my $commentid = shift;
    my $userid    = shift;

    $self -> clear_error();

    my $checkh = $self -> {"dbh"} -> prepare("SELECT *
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_comments"}."`
                                              WHERE comment_id = ?
                                              AND marked_id = ?
                                              AND cancelled IS NULL");
    $checkh -> execute($commentid, $userid)
        or return $self -> self_error("Unable to execute helpful history lookup for user $userid: ".$self -> {"dbh"} -> errstr);

    my $rated = $checkh -> fetchrow_hashref();

    return $rated ? $rated : {};
}


## @method private @ _get_comment_stats($id, $type)
# Obtain the count of comments attached to the specified question or answer, and the
# timestamp of the latest comment edit.
#
# @param id   The ID of the question or answer to fetch comment stats for.
# @param type The type of entry to get stats for, must be "question" or "answer"
# @return An array of two values: the number of comments, and the
sub _get_comment_stats {
    my $self = shift;
    my $id   = shift;
    my $type = shift;

    $self -> clear_error();

    # Force a legal type
    $type = "question" unless(defined($type) && $type eq "answer");

    # Get the number of non-deleted comments attached to the question or answer
    my $comstath = $self -> {"dbh"} -> prepare("SELECT COUNT(r.comment_id), MAX(c.updated)
                                                FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_${type}s_comments"}."` AS r,
                                                     `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_comments"}."` AS c
                                                WHERE r.${type}_id = ?
                                                AND c.id = r.comment_id
                                                AND c.deleted IS NULL");
    $comstath -> execute($id)
        or return ($self -> self_error("Unable to execute comment stats query: ".$self -> {"dbh"} -> errstr), undef);

    my $stats = $comstath -> fetchrow_arrayref()
        or return ($self -> self_error("Stats query did not return sane values."), undef);

    return (@{$stats});
}


## @method private $ _sync_counts($questionid)
# Recalculate the number of answers and comments on the specified question, and the
# latest post times of both.
#
# @parma questionid The ID of the question to resync.
# @return true on success, undef otherwise.
sub _sync_counts {
    my $self       = shift;
    my $questionid = shift;

    $self -> clear_error();

    # Counters and stuff to store the stats in
    my $answers        = 0;
    my $latest_answer  = undef;
    my $comments       = 0;
    my $latest_comment = undef;

    ($comments, $latest_comment) = $self -> _get_comment_stats($questionid, "question");
    return undef if(!defined($comments));

    # Now fetch the answer headers, and calculate their comments too
    my $ansh = $self -> {"dbh"} -> prepare("SELECT id, updated
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_answers"}."`
                                            WHERE question_id = ?
                                            AND deleted IS NULL");
    $ansh -> execute($questionid)
        or return $self -> self_error("Unable to execute answer lookup: ".$self -> {"dbh"} -> errstr);

    while(my $answer = $ansh -> fetchrow_hashref()) {
        # record the answer, and update the timestamp if needed
        ++$answers;
        $latest_answer = $answer -> {"updated"} if($answer -> {"updated"} > $latest_answer);

        # And fetch the stats for the answer's comments
        my ($count, $latest) = $self -> _get_comment_stats($answer -> {"id"}, "answer");
        return undef if(!defined($count));

        $comments += $count;
        $latest_comment = $latest if($latest > $latest_comment);
    }

    # When was the question itself updated?
    my $timeh = $self -> {"dbh"} -> prepare("SELECT updated
                                             FROM  `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_questions"}."`
                                             WHERE id = ?");
    $timeh -> execute($questionid)
        or return $self -> self_error("Unable to execute question update lookup: ".$self -> {"dbh"} -> errstr);

    my $updated = $timeh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to fetch update time for question $questionid: entry does not exist.");

    # Work out what the latest update was across everything.
    my @times = ($latest_answer, $latest_comment, $updated -> [0]);
    $updated = max(@times);

    # Now update the question
    my $seth = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"feature::qaforums_questions"}."`
                                            SET answers = ?, comments = ?, latest_answer = ?, latest_comment = ?, updated = ?
                                            WHERE id = ?");
    my $result = $seth -> execute($answers, $comments, $latest_answer, $latest_comment, $updated, $questionid);
    return $self -> self_error("Unable to perform question stats update: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Question stats update failed, no rows updated") if($result eq "0E0");

    return 1;
}

1;
