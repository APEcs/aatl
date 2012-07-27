## @file
# This file contains the implementation of the AATL QA Forum feature class.
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

## @class Feature::QAForums
#
package Feature::QAForums;

use strict;
use base qw(Feature);
use System::QAForums;
use POSIX qw(ceil);
use HTML::Scrubber;
use Data::Dumper;

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
    $self -> {"qaforums"} = System::QAForums -> new(dbh      => $self -> {"dbh"},
                                                    settings => $self -> {"settings"},
                                                    logger   => $self -> {"logger"},
                                                    roles    => $self -> {"system"} -> {"roles"},
                                                    metadata => $self -> {"system"} -> {"metadata"},
                                                    courses  => $self -> {"system"} -> {"courses"})
        or return SystemModule::set_error("Forum initialisation failed: ".$System::News::errstr);

    # FIXME: This will probably need to instantiate the tags feature to get at Feature::Tags::block_display().
    # $self -> {"tags"} = $self -> {"modules"} -> load_module("Feature::Tags");

    # Cache the courseid for later
    $self -> {"courseid"} = $self -> determine_courseid();

    # Precalculate the tab bar information for later
    $self -> {"tabbar"} = [ { "mode"    => "updated",
                              "url"     => $self -> build_url(block => "qaforum", pathinfo => ["updated"]),
                              "text"    => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_TAB_ACTIVE"),
                              "title"   => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_TITLE_ACTIVE"),
                              "reqperm" => "qaforums.read",
                            },
                            { "mode"    => "created",
                              "url"     => $self -> build_url(block => "qaforum", pathinfo => ["created"]),
                              "text"    => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_TAB_LATEST"),
                              "title"   => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_TITLE_LATEST"),
                              "reqperm" => "qaforums.read",
                            },
                            { "mode"    => "rating",
                              "url"     => $self -> build_url(block => "qaforum", pathinfo => ["rating"]),
                              "text"    => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_TAB_RATED"),
                              "title"   => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_TITLE_RATED"),
                              "reqperm" => "qaforums.read",
                            },
                            { "mode"    => "unanswered",
                              "url"     => $self -> build_url(block => "qaforum", pathinfo => ["unanswered"]),
                              "text"    => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_TAB_NOANS"),
                              "title"   => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_TITLE_NOANS"),
                              "reqperm" => "qaforums.read",
                            },
                            { "mode"    => "faq",
                              "url"     => $self -> build_url(block => "qaforum", pathinfo => ["faq"]),
                              "text"    => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_TAB_FAQS"),
                              "title"   => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_TITLE_FAQS"),
                              "reqperm" => "qaforums.read",
                            },
                            { "mode"    => "ask",
                              "url"     => $self -> build_url(block => "qaforum", pathinfo => ["ask"]),
                              "text"    => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_TAB_ASK"),
                              "title"   => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_TITLE_ASK"),
                              "reqperm" => "qaforums.ask",
                            },
        ];

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

    return { "qaforums.read"        => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.READ"),
             "qaforums.ask"         => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.ASK"),
             "qaforums.answer"      => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.ANSWER"),
             "qaforums.comment"     => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.COMMENT"),
             "qaforums.answer"      => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.ANSWER"),
             "qaforums.editown"     => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.EDITOWN"),
             "qaforums.editother"   => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.EDITOTHER"),
             "qaforums.deleteown"   => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.DELETEOWN"),
             "qaforums.deleteother" => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.DELETEOTHER"),
             "qaforums.rate"        => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.RATE"),
             "qaforums.flag"        => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.FLAG"),
             "qaforums.unflag"      => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.UNFLAG"),
             "qaforums.tag"         => $self -> {"template"} -> replace_langvar("CAPABILITY_QAFORUM.TAG"),
           };
}



# ============================================================================
#  General utility code

## @method private $ _build_tab_bar($mode)
# Generate the tab bar to show above question lists, etc.
#
# @param mode The mode to set, must be one of the modes present in $self -> {"tabbar"}
# @return The tab bar html
sub _build_tab_bar {
    my $self = shift;
    my $mode = shift;

    my $metadataid = $self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"});
    my $userid     = $self -> {"session"} -> get_session_userid();

    # Activate the appropriate entry in the tab bar first
    my $acttitle = "";
    foreach my $tab (@{$self -> {"tabbar"}}) {
        if($tab -> {"visible"} = $self -> {"qaforums"} -> check_permission($metadataid, $userid, $tab -> {"reqperm"})) {
            $tab -> {"active"} = ($mode eq $tab -> {"mode"});
            $acttitle = $tab -> {"title"} if($tab -> {"active"});
        }
    }

    return $self -> tab_bar($self -> {"tabbar"}, 1);
}


## @method private $ _nice_value($value)
# Convert the specified value to a more readable string. If the value exceeds
# 3 digits it is represnted in 'k'. If it exceeds 6 digits, it is represented as
# 'm'
#
# @param value The value to convert
# @return A string containing the converted value
sub _nice_value {
    my $self  = shift;
    my $value = shift;

    if($value < 1000) {
        return $value;
    } elsif($value < 100000) {
        return sprintf("%.1fk", $value / 1000);
    } elsif($value < 1000000) {
        return sprintf("%dk", $value / 1000);
    } else {
        return sprintf("%.1fm", $value / 1000000);
    }
}


# ============================================================================
#  Question viewing

## @method private @ _show_question_list($mode, $page)
# Generate a list of questions to show the user. This will generate a paginated list
# of visible (ie: non-deleted) questions posted in the current course's forums.
#
# @param mode The view mode, should be "updated", "created", "rating", or "unanswered"
# @param page The page number to show. This in the range 1 <= page <= maxpages, and will
#             be clamped if out of range.
# @return Three values: the page title, the content to show in the page, and the extra
#         css and javascript directives to place in the header.
sub _show_question_list {
    my $self = shift;
    my $mode = shift;
    my $page = shift || 1;

    # If the page has been set, make sure it is numeric
    $page = 1 unless($page =~ /^\d+$/);

    my ($tabs, $acttitle) = $self -> _build_tab_bar($mode);

    # How many questions need to be shown?
    my $count = $self -> {"qaforums"} -> get_question_count($self -> {"courseid"}, $mode eq "unanswered");
    $self -> {"logger"} -> die_log($self -> {"cgi"} -> remote_host(), "Fatal error: ".$self -> {"qaforums"} -> {"errstr"})
        if(!defined($count));

    # Make sure that pagination is sane
    my $pagesize = ($self -> {"settings"} -> {"config"} -> {"Feature::QAForums::question_count"} || 15);
    my $maxpage  = ceil($count / $pagesize);
    $page = 1 if($page < 1);
    $page = $maxpage if($page > $maxpage);

    my $pagination = $self -> build_pagination($maxpage, $page, $mode, $self -> {"settings"} -> {"config"} -> {"pagination_width"});

    # Work out what the list mode should be
    my $listmode = $mode;
    $listmode = "created" if($mode eq "unanswered");

    # Fetch the question list
    my $questions = $self -> {"qaforums"} -> get_question_list($self -> {"courseid"},
                                                               {"mode"     => $listmode,
                                                                "noanswer" => $mode eq "unanswered",
                                                                "offset"   => ($page - 1) * $pagesize,
                                                                "count"    => $pagesize})
        or $self -> {"logger"} -> die_log($self -> {"cgi"} -> remote_host(), "Fatal error: ".$self -> {"qaforums"} -> {"errstr"});

    my $qlist = "";
    my $questiontem = $self -> {"template"} -> load_template("feature/qaforums/questionlist_question.tem");
    my $scrubber = HTML::Scrubber -> new();

    foreach my $question (@{$questions}) {
        my $asker  = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byid($question -> {"creator_id"});

        # Work out what state the question is in for styling
        my $status = "unanswered";
        $status  = "answered" if($question -> {"answers"});
        $status .= " chosen"  if($question -> {"best_answer_id"});

        # Strip any html from the string
        my $preview = $scrubber -> scrub($question -> {"message"});
        $preview = $self -> {"template"} -> truncate_words($preview, $self -> {"settings"} -> {"config"} -> {"Feature::QAForums::preview_length"});

        # Work out any 'answered', 'updated' data...
        my $extrainfo = "";

        $qlist .= $self -> {"template"} -> process_template($questiontem, {"***qid***"       => $question -> {"id"},
                                                                           "***url***"       => $self -> build_url(block => "qaforum", pathinfo => [ "question", $question -> {"id"} ]),
                                                                           "***rating***"    => $self -> _nice_value($question -> {"rating"}),
                                                                           "***status***"    => $status,
                                                                           "***answers***"   => $question -> {"answers"},
                                                                           "***rawviews***"  => $question -> {"views"},
                                                                           "***views***"     => $self -> _nice_value($question -> {"views"}),
                                                                           "***subject***"   => $question -> {"subject"},
                                                                           "***preview***"   => $preview,
                                                                           "***extrainfo***" => $extrainfo,
                                                                           "***asked***"     => $self -> {"template"} -> format_time($question -> {"created"}),
                                                                           "***profile***"   => $self -> build_url(block => "profile", pathinfo => [ $asker -> {"username"} ]),
                                                                           "***name***"      => $asker -> {"fullname"},
                                                                           "***gravhash***"  => $asker -> {"gravatar_hash"},
                                                            });
    }

    return ($self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_QLIST_TITLE", {"***title***" => $acttitle}),
            $self -> {"template"} -> load_template("feature/qaforums/questionlist_container.tem",
                                                   {"***error***"      => "",
                                                    "***tabs***"       => $tabs,
                                                    "***pagination***" => $pagination,
                                                    "***contents***"   => $self -> {"template"} -> load_template("feature/qaforums/questionlist_list.tem",
                                                                                                                 {"***contents***" => $qlist}),
                                                   }),
            $self -> {"template"} -> load_template("feature/qaforums/extrahead.tem"));
}


## @method private @ _build_comments($id, $type, $permissions)
# Generate the block of questions currently set for the specified question
# or answer.
#
# @param id          The ID of the question or answer to build the comment block for.
# @param type        The type of entry the ID refers to, must be "question" or "answer".
# @param permissions A hash containing the user's permissions.
# @return A block of html containing the comment list and controls.
sub _build_comments {
    my $self        = shift;
    my $id          = shift;
    my $type        = shift;
    my $permissions = shift;

    my $comments = $self -> {"qaforums"} -> get_comments($id, $type);

    my $commtem = $self -> {"template"} -> load_template("feature/qaforums/question_comment.tem");

    my $qlist = "";
    foreach my $comment (@$comments) {
        my $commenter = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byid($comment -> {"creator_id"});

        $qlist .= $self -> {"template"} -> process_template($commtem, {"***cid***"      => $comment -> {"id"},
                                                                       "***helpfuls***" => $comment -> {"helpful"},
                                                                       "***helpop***"   => "",
                                                                       "***flagop***"   => "",
                                                                       "***deleteop***" => "",
                                                                       "***message***"  => $comment -> {"message"},
                                                                       "***profile***"  => $self -> build_url(block => "profile", pathinfo => [ $commenter -> {"username"} ]),
                                                                       "***name***"     => $commenter -> {"fullname"},
                                                            });
    }

    my $qform = "";
    $qform = $self -> {"template"} -> load_template("feature/qaforums/comment_form.tem", {"***id***"   => $id,
                                                                                          "***mode***" => $type});

    return $self -> {"template"} -> load_template("feature/qaforums/question_comments.tem", {"***comments***"    => $qlist,
                                                                                             "***commentform***" => $qform});
}


## @method private @ _show_question($questionid)
# Generate a page containing the specified question, its answers and comments.
#
# @param questionid The ID of the question to show.
# @return Three values: the page title, the content to show in the page, and the extra
#         css and javascript directives to place in the header.
sub _show_question {
    my $self       = shift;
    my $questionid = shift;
    my $userid     = $self -> {"session"} -> get_session_userid(); # cache the user for permission checks

    my ($tabs, $acttitle) = $self -> _build_tab_bar("");

    # The questionid must be numeric to fetch the question data
    my $question = $self -> {"qaforums"} -> get_question($self -> {"courseid"}, $questionid)
        if($questionid =~ /^\d+$/);

    # If there is no question here, return an error
    if(!defined($question)) {
        return ($self -> {"template"} -> replace_langvar("FEATURE_QVIEW_ERROR_TITLE"),
                $self -> {"template"} -> message_box("{L_FEATURE_QVIEW_ERROR_TITLE}",
                                                     "error",
                                                     "{L_FEATURE_QVIEW_ERROR}",
                                                     "{L_FEATURE_QVIEW_NOQUESTION}",
                                                     undef,
                                                     "errorcore",
                                                     [ {"message" => $self -> {"template"} -> replace_langvar("SITE_CONTINUE"),
                                                        "colour"  => "blue",
                                                        "action"  => "location.href='".$self -> build_url(block => "news")."'"} ]),
                $self -> {"template"} -> load_template("feature/qaforums/extrahead.tem"))
    }

    my ($questionblock, $answerblock, $answerform) = ("", "", "");

    # Check some permissions
    my $permissions = {
        "rate"        => $self -> {"qaforums"} -> check_permission($question -> {"metadata_id"}, $userid, "qaforums.rate"),
        "flag"        => $self -> {"qaforums"} -> check_permission($question -> {"metadata_id"}, $userid, "qaforums.flag"),
        "unflag"      => $self -> {"qaforums"} -> check_permission($question -> {"metadata_id"}, $userid, "qaforums.unflag"),
        "answer"      => $self -> {"qaforums"} -> check_permission($question -> {"metadata_id"}, $userid, "qaforums.answer"),
        "comment"     => $self -> {"qaforums"} -> check_permission($question -> {"metadata_id"}, $userid, "qaforums.comment"),
        "editown"     => $self -> {"qaforums"} -> check_permission($question -> {"metadata_id"}, $userid, "qaforums.editown"),
        "editother"   => $self -> {"qaforums"} -> check_permission($question -> {"metadata_id"}, $userid, "qaforums.editother"),
        "deleteown"   => $self -> {"qaforums"} -> check_permission($question -> {"metadata_id"}, $userid, "qaforums.deleteown"),
        "deleteother" => $self -> {"qaforums"} -> check_permission($question -> {"metadata_id"}, $userid, "qaforums.deletether"),
    };

    # Potentially disable delete anyway if the question has answers or comments.
    $permissions -> {"deleteown"}   = $permissions -> {"deleteown"}   && ($question -> {"answers"} == 0) && ($question -> {"comments"} == 0);
    $permissions -> {"deleteother"} = $permissions -> {"deleteother"} && ($question -> {"answers"} == 0) && ($question -> {"comments"} == 0);

    my $asker  = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byid($question -> {"creator_id"});

    my ($rateup, $ratedown) = ("", "");
    if($permissions -> {"rate"}) {
        $rateup   = $self -> {"template"} -> load_template("feature/qaforums/rateup.tem");
        $ratedown = $self -> {"template"} -> load_template("feature/qaforums/ratedown.tem");
    }

    my $rated = $self -> {"qaforums"} -> user_has_rated_question($questionid, $userid);

    # Generate the question block
    $questionblock = $self -> {"template"} -> load_template("feature/qaforums/question_question.tem",
                                                            {"***qid***"       => $question -> {"id"},
                                                             "***rating***"    => $question -> {"rating"},
                                                             "***rateup***"    => $self -> {"template"} -> process_template($rateup  , {"***active***" => ($rated eq "up" ? "rated" : ""),
                                                                                                                                        "***id***"     => "rup-qid-".$question -> {"id"},
                                                                                                                                        "***title***"  => "{L_FEATURE_QVIEW_QRUP}"}),
                                                             "***ratedown***"  => $self -> {"template"} -> process_template($ratedown, {"***active***" => ($rated eq "down" ? "rated" : ""),
                                                                                                                                        "***id***"     => "rdn-qid-".$question -> {"id"},
                                                                                                                                        "***title***"  => "{L_FEATURE_QVIEW_QRDOWN}"}),
                                                             "***locked***"    => "", # TODO
                                                             "***url***"       => $self -> build_url(block => "qaforum", pathinfo => [ "question", $question -> {"id"} ]),
                                                             "***subject***"   => $question -> {"subject"},
                                                             "***message***"   => $question -> {"message"},
                                                             "***extrainfo***" => "", # TODO
                                                             "***profile***"   => $self -> build_url(block => "profile", pathinfo => [ $asker -> {"username"} ]),
                                                             "***asked***"     => $self -> {"template"} -> format_time($question -> {"created"}),
                                                             "***name***"      => $asker -> {"fullname"},
                                                             "***gravhash***"  => $asker -> {"gravatar_hash"},
                                                             "***comments***"  => $self -> _build_comments($question -> {"id"}, "question"),
                                                            });

    # If the user can answer, add the form for that
    $answerform = $self -> {"template"} -> load_template("feature/qaforums/question_answerform.tem", {"***qid***" => $question -> {"id"},
                                                                                                      "***message***" => ""
                                                         })
        if($permissions -> {"answer"});

    return ($self -> {"template"} -> replace_langvar("FEATURE_QVIEW_TITLE", {"***title***" => $question -> {"subject"}}),
            $self -> {"template"} -> load_template("feature/qaforums/questionlist_container.tem",
                                                   {"***error***"      => "",
                                                    "***tabs***"       => $tabs,
                                                    "***pagination***" => "",
                                                    "***contents***"   => $self -> {"template"} -> load_template("feature/qaforums/question_contents.tem",
                                                                                                                 {"***question***"   => $questionblock,
                                                                                                                  "***answers***"    => $answerblock,
                                                                                                                  "***answerform***" => $answerform}),
                                                   }),
            $self -> {"template"} -> load_template("feature/qaforums/extrahead.tem"));


}


# ============================================================================
#  Question validation and addition

## @method private $ _validate_question_fields($args)
# Validate the subject and message fields submitted by the user.
#
# @param args A reference to a hash to store validated data in.
# @return undef on success, otherwise an error string.
sub _validate_question_fields {
    my $self = shift;
    my $args = shift;
    my ($errors, $error) = ("", "");

    my $errtem = $self -> {"template"} -> load_template("error_item.tem");

    ($args -> {"subject"}, $error) = $self -> validate_string("subject", {"required" => 1,
                                                                          "nicename" => $self -> {"template"} -> replace_langvar("FEATURE_NEWS_SUBJECT"),
                                                                          "minlen"   => 1,
                                                                          "maxlen"   => 255});
    $errors .= $self -> {"template"} -> process_template($errtem, {"***error***" => $error}) if($error);

    ($args -> {"message"}, $error) = $self -> validate_htmlarea("message", {"required" => 1,
                                                                            "validate" => $self -> {"config"} -> {"Core:validate_htmlarea"}});
    $errors .= $self -> {"template"} -> process_template($errtem, {"***error***" => $error}) if($error);

    return $errors ? $errors : undef;
}


## @method private $ _validate_question()
# Validate the subject and message submitted by the user, and potentially add
# a new question to the system. Note that this will not return if the question
# fields validate; it will redirect the user to the new question and exit.
#
# @return An error message, and a reference to a hash containing
#         the fields that passed validation.
sub _validate_question {
    my $self = shift;
    my ($args, $errors, $error) = ({}, "", "");

    my $errtem = $self -> {"template"} -> load_template("error_item.tem");

    # Exit with a permission error unless the user has permission to post
    my $canpost = $self -> {"qaforums"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                            $self -> {"session"} -> get_session_userid(),
                                                            "qaforums.ask");
    return ($self -> {"template"} -> load_template("error_list.tem",
                                                   {"***message***" => "{L_FEATURE_QAFORUM_ASK_FAILED}",
                                                    "***errors***"  => $self -> {"template"} -> process_template($errtem,
                                                                                                                 {"***error***" => "{L_FEATURE_QAFORUM_ASK_ERRPERM}"})}),
            $args) unless($canpost);

    $error = $self -> _validate_question_fields($args);
    $errors += $error if($error);

    # Give up here if there are any errors
    return ($self -> {"template"} -> load_template("error_list.tem",
                                                   {"***message***" => "{L_FEATURE_QAFORUM_ASK_FAILED}",
                                                    "***errors***"  => $errors}), $args)
        if($errors);

    # No errors, try adding the question
    my $qid = $self -> {"qaforums"} -> create_question($self -> {"courseid"},
                                                       $self -> {"session"} -> get_session_userid(),
                                                       $args -> {"subject"},
                                                       $args -> {"message"});
    return ($self -> {"template"} -> load_template("error_list.tem",
                                                   {"***message***" => "{L_FEATURE_QAFORUM_ASK_FAILED}",
                                                    "***errors***"  => $self -> {"template"} -> process_template($errtem,
                                                                                                                 {"***error***" => $self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_ASK_ERROR", {"***error***" => $self -> {"qaforums"} -> {"errstr"}})
                                                                                                                 })
                                                   }),
            $args)
        unless($qid);

    print $self -> {"cgi"} -> redirect($self -> build_url(block => "qaforum", pathinfo => ["question", $qid]));
    exit;
}


## @method private $ _ask_question()
# Generate the 'ask a question' form.
#
# @return Three values: the page title, the content to show in the page, and the extra
#         css and javascript directives to place in the header.
sub _ask_question {
    my $self    = shift;
    my $content = "";
    my $error   = "";
    my $args    = {};

    # Activate the appropriate entry in the tab bar first
    my ($tabs, $acttitle) = $self -> _build_tab_bar("ask");

    if($self -> {"cgi"} -> param("newquest")) {
        ($error, $args) = $self -> _validate_question();
    }

    $content = $self -> {"template"} -> load_template("feature/qaforums/askform.tem", {"***url***" => $self -> build_url(block => "qaforum", pathinfo => ["ask"]),
                                                                                       "***subject***" => $args -> {"subject"},
                                                                                       "***message***" => $args -> {"message"},
                                                      });
    # Wrap the errors if needed
    $error = $self -> {"template"} -> load_template("feature/qaforums/error_box.tem", {"***message***" => $error})
        if($error);

    # put everything together to send back
    return ($self -> {"template"} -> replace_langvar("FEATURE_QAFORUM_ASK_TITLE"),
            $self -> {"template"} -> load_template("feature/qaforums/questionlist_container.tem",
                                                   {"***error***"      => $error,
                                                    "***tabs***"       => $tabs,
                                                    "***pagination***" => "",
                                                    "***contents***"   => $content,
                                                   }),
            $self -> {"template"} -> load_template("feature/qaforums/extrahead.tem"));
}



# ============================================================================
#  Answer validation and addition

## @method private $ _validate_answer_fields($args)
# Validate the message field submitted by the user.
#
# @param args A reference to a hash to store validated data in.
# @return undef on success, otherwise an error string.
sub _validate_answer_fields {
    my $self = shift;
    my $args = shift;
    my ($errors, $error) = ("", "");

    my $errtem = $self -> {"template"} -> load_template("error_item.tem");

    ($args -> {"message"}, $error) = $self -> validate_htmlarea("message", {"required" => 1,
                                                                            "validate" => $self -> {"config"} -> {"Core:validate_htmlarea"}});
    $errors .= $self -> {"template"} -> process_template($errtem, {"***error***" => $error}) if($error);

    return $errors ? $errors : undef;
}


# ============================================================================
#  API implementation

## @method private $ _build_api_rating_response($op)
# Update the rate attached the entry selected by the user. This supports rating
# of both questions and answers, based on the ID provided to the api call.
#
# @param op The operation to apply, must be "rup" or "rdn"
# @return A hash containing the API response to return to the user. Should be
#         passed to api_response().
sub _build_api_rating_response {
    my $self   = shift;
    my $op     = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    # convert the op to a more readable direction for convenience
    my $opdir = ($op eq "rup" ? "up" : "down");

    # Get the ID and parse out the mode and id
    my $fullid = $self -> {"cgi"} -> param("id")
        or return $self -> api_errorhash("no_postid", $self -> {"template"} -> replace_langvar("FEATURE_QVIEW_APIRATE_NOID"));

    my ($mode, $id) = $fullid =~ /^(aid|qid)-(\d+)$/;
    return $self -> api_errorhash("bad_id", $self -> {"template"} -> replace_langvar("FEATURE_QVIEW_APIRATE_BADID"))
        unless($mode && $id);

    $mode = ($mode eq "qid" ? "question" : "answer");

    # Check the user can rate
    my $metadataid = $self -> {"qaforums"} -> get_metadataid($id, $mode)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("FEATURE_QVIEW_API_ERROR", {"***error***" => $self -> {"qaforums"} -> {"errstr"}}));

    return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_QVIEW_APIRATE_PERMS"))
        unless($self -> {"qaforums"} -> check_permission($metadataid, $userid, "qaforums.rate"));

    # Determine whether the user has rated the question or answer
    my $rated = $self -> {"qaforums"} -> user_has_rated($id, $mode, $userid);
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("FEATURE_QVIEW_API_ERROR", {"***error***" => $self -> {"qaforums"} -> {"errstr"}}))
        if(!defined($rated));

    # if the user has rated the question or answer, cancel it
    my $newrating = $self -> {"qaforums"} -> unrate($id, $mode, $userid) if($rated);

    # If the op indicates rating in a different direction to a previous rating, do it
    $self -> {"qaforums"} -> rate($id, $mode, $userid, $opdir)
        if($opdir ne $rated);

    $rated = $self -> {"qaforums"} -> user_has_rated($id, $mode, $userid);

    # Get the current rating...
    my $rating = $self -> {"qaforums"} -> get_rating($id, $mode);
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("FEATURE_QVIEW_API_ERROR", {"***error***" => $self -> {"qaforums"} -> {"errstr"}}))
        if(!defined($rating));

    return { 'rated' => { "up"     => ($rated eq "up" ? "set" : ""),
                          "down"   => ($rated eq "down" ? "set" : ""),
                          "rating" => $rating} };
}


## @method $ _build_api_answer_add_response()
# Attempt to add and answer to a question. This will validate that the data submitted by
# the user is valid, and if so it will add the answer and send back the answer fragment to
# embed in the page.
#
# @return
sub _build_api_answer_add_response {
    my $self   = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    # The question ID should be provided by the query
    my $qid = $self -> {"cgi"} -> param("id")
        or return $self -> api_errorhash("no_postid", $self -> {"template"} -> replace_langvar("FEATURE_QVIEW_APIANS_NOID"));

    # Check that the user has permission to answer the question.
    my $metadataid = $self -> {"qaforums"} -> get_metadataid($id, "question")
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("FEATURE_QVIEW_API_ERROR", {"***error***" => $self -> {"qaforums"} -> {"errstr"}}));

    return $self -> api_errorhash("bad_perm", $self -> {"template"} -> replace_langvar("FEATURE_QVIEW_APIANS_PERMS"))
        unless($self -> {"qaforums"} -> check_permission($metadataid, $userid, "qaforums.answer"));


}


# ============================================================================
#  Interface

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
    my $canread = $self -> {"qaforums"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                            $self -> {"session"} -> get_session_userid(),
                                                            "qaforums.read");
    if(!$canread) {
        my $userbar = $self -> {"module"} -> load_module("Feature::Userbar");
        my $message = $self -> {"template"} -> message_box("{L_FEATURE_QAFORUM_VIEWPERM_TITLE}",
                                                           "error",
                                                           "{L_FEATURE_QAFORUM_VIEWPERM}",
                                                           "",
                                                           undef,
                                                           "errorcore",
                                                           [ {"message" => $self -> {"template"} -> replace_langvar("SITE_CONTINUE"),
                                                              "colour"  => "blue",
                                                              "action"  => "location.href='".$self -> build_url(block => "news")."'"} ]);

        return $self -> {"template"} -> load_template("error/general.tem",
                                                      {"***title***"     => "{L_FEATURE_QAFORUM_VIEWPERM_TITLE}",
                                                       "***message***"   => $message,
                                                       "***extrahead***" => "",
                                                       "***userbar***"   => $userbar -> block_display(),
                                                      })
    }

    # Is this an API call, or a normal news page call?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {
        if($apiop eq "rup" || $apiop eq "rdn") {
            return $self -> api_response($self -> _build_api_rating_response($apiop));
        } else {
            return $self -> api_html_response($self -> api_errorhash('bad_op',
                                                                     $self -> {"template"} -> replace_langvar("API_BAD_OP")))
        }

    } else {
        my @pathinfo = $self -> {"cgi"} -> param('pathinfo');

        # Note that the mode parameters to show_question_list() could conceivably
        # be set straight from $pathinfo[0] when appropriate, that has Tainting Issues.
        if(!scalar(@pathinfo) || $pathinfo[0] eq "updated") {
            ($title, $content, $extrahead) = $self -> _show_question_list("updated"   , $pathinfo[1]);
        } elsif($pathinfo[0] eq "created") {
            ($title, $content, $extrahead) = $self -> _show_question_list("created"   , $pathinfo[1]);
        } elsif($pathinfo[0] eq "rating") {
            ($title, $content, $extrahead) = $self -> _show_question_list("rating"    , $pathinfo[1]);
        } elsif($pathinfo[0] eq "unanswered") {
            ($title, $content, $extrahead) = $self -> _show_question_list("unanswered", $pathinfo[1]);
        } elsif($pathinfo[0] eq "ask") {
            ($title, $content, $extrahead) = $self -> _ask_question();
        } elsif($pathinfo[0] eq "question") {
            ($title, $content, $extrahead) = $self -> _show_question($pathinfo[1]);
        }

        # User has access, generate the news page for the course.
        return $self -> generate_course_page($title, $content, $extrahead);
    }
}

1;
