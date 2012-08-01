## @file
# This file contains the implementation of the AATL news feature class.
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

## @class Feature::News
#
package Feature::News;

use strict;
use base qw(Feature);
use System::News;
use Utils qw(is_defined_numeric);

# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Overloaded constructor for News posts, loads the System::News model and other
# classes required to generate the news page.
#
# @param args A hash of values to initialise the object with. See the Block docs
#             for more information.
# @return A reference to a new Feature::News object on success, undef on error.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_)
        or return undef;

    # Create a news model to work through.
    $self -> {"news"} = System::News -> new(dbh      => $self -> {"dbh"},
                                            settings => $self -> {"settings"},
                                            logger   => $self -> {"logger"},
                                            roles    => $self -> {"system"} -> {"roles"},
                                            metadata => $self -> {"system"} -> {"metadata"},
                                            courses  => $self -> {"system"} -> {"courses"})
        or return SystemModule::set_error("News initialisation failed: ".$System::News::errstr);

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

    return { "news.post"        => $self -> {"template"} -> replace_langvar("CAPABILITY_NEWS.POST"),
             "news.editown"     => $self -> {"template"} -> replace_langvar("CAPABILITY_NEWS.EDITOWN"),
             "news.editother"   => $self -> {"template"} -> replace_langvar("CAPABILITY_NEWS.EDITOTHER"),
             "news.deleteown"   => $self -> {"template"} -> replace_langvar("CAPABILITY_NEWS.EDITOWN"),
             "news.deleteother" => $self -> {"template"} -> replace_langvar("CAPABILITY_NEWS.EDITOTHER"),
           };
}


# ============================================================================
#  Validation

## @method private $ _validate_fields($args)
# Validate the subject and message fields submitted by the user.
#
# @param args A reference to a hash to store validated data in.
# @return undef on success, otherwise an error string.
sub _validate_fields {
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
                                                                            "minlen"   => 8,
                                                                            "nicename" => $self -> {"template"} -> replace_langvar("FEATURE_NEWS_MESSAGE"),
                                                                            "validate" => $self -> {"config"} -> {"Core:validate_htmlarea"}});
    $errors .= $self -> {"template"} -> process_template($errtem, {"***error***" => $error}) if($error);

    return $errors ? $errors : undef;
}


## @method @ validate_news_post()
# Determine whether the user has permission to post news posts, and if they do
# validate the data they have submitted.
#
# @return An array of two values: an error message on failure and a reference to
#         a hash containing any submitted values that passed validation. Does not
#         return on successful news posting.
sub validate_news_post {
    my $self = shift;
    my ($args, $errors, $error) = ({}, "", "");

    my $errtem = $self -> {"template"} -> load_template("error_item.tem");

    # Exit with a permission error unless the user has permission to post
    my $canpost = $self -> {"news"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                        $self -> {"session"} -> get_session_userid(),
                                                        "news.post");
    return ($self -> {"template"} -> load_template("error_list.tem",
                                                   {"***message***" => "{L_FEATURE_NEWS_ERR_POSTFAIL}",
                                                    "***errors***"  => $self -> {"template"} -> process_template($errtem,
                                                                                                                 {"***error***" => "{L_FEATURE_NEWS_ERR_POSTPERM}"})}),
            $args) unless($canpost);

    $error = $self -> _validate_fields($args);
    $errors .= $error if($error);

    # Give up here if there are any errors
    return ($self -> {"template"} -> load_template("error_list.tem",
                                                   {"***message***" => "{L_FEATURE_NEWS_ERR_POSTFAIL}",
                                                    "***errors***"  => $errors}), $args)
        if($errors);

    # No errors so far, try creating the new post
    my $post = $self -> {"news"} -> create_post($self -> {"courseid"},
                                                $self -> {"session"} -> get_session_userid(),
                                                $args -> {"subject"},
                                                $args -> {"message"})
        or return ($self -> {"template"} -> load_template("error_list.tem",
                                                   {"***message***" => "{L_FEATURE_NEWS_ERR_POSTFAIL}",
                                                    "***errors***"  => $self -> {"template"} -> process_template($errtem,
                                                                                                                 {"***error***" => $self -> {"news"} -> {"errstr"}})}),
                   $args);

    $self -> log("news:add", "Added news post ".$post -> {"id"});

    print $self -> {"cgi"} -> redirect($self -> build_url(block => "news"));
    exit;
}


# ============================================================================
#  News posts

## @method $ build_newpost_form($args)
# Determine whether the user has access to post new news entries, and if the
# user does generate the appropriate chunk of HTML.
#
# @param args A reference to a hash containing initial values for the subject
#             and message fields in the form.
# @return The HTML to place in the new post form area
sub build_newpost_form {
    my $self = shift;
    my $args = shift || {};

    # Does the user have permission to post news posts in this course?
    my $canpost = $self -> {"news"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                        $self -> {"session"} -> get_session_userid(),
                                                        "news.post");
    return undef if(!defined($canpost));

    # Specifying a postid means that the user has linked a specific post. In that situation,
    # should posting should be disabled?
    $canpost = $canpost && !defined($self -> {"cgi"} -> param("postid"))
        unless($self -> {"settings"} -> {"config"} -> {"Feature::News::always_post"});

    return $self -> {"template"} -> load_template("feature/news/postform_".($canpost ? "enabled" : "disabled").".tem",
                                                  {"***url***"     => $self -> build_url(block => "news"),
                                                   "***subject***" => $args -> {"subject"},
                                                   "***message***" => $args -> {"message"}});
}


## @method $ build_post_controls($post)
# Generate the controls the user may use to operate on the specified post, if any.
#
# @param post A reference to a hash containing the post data.
# @return A string containing the controls block to show in the post html.
sub build_post_controls {
    my $self = shift;
    my $post = shift;

    my $user    = $self -> {"session"} -> get_session_userid();
    my $options = "";

    # Is the post owned by the current user, or someone else?
    my $ownership = ($post -> {"creator_id"} == $user ? "own" : "other");

    # What permissions does the user have on the post?
    my $canedit   = ($self -> {"news"} -> check_permission($post -> {"metadata_id"}, $user, "news.edit$ownership")   ? "enabled" : "disabled");
    my $candelete = ($self -> {"news"} -> check_permission($post -> {"metadata_id"}, $user, "news.delete$ownership") ? "enabled" : "disabled");

    $options .= $self -> {"template"} -> load_template("feature/news/controls/edit_${canedit}.tem", {"***postid***" => $post -> {"id"}});
    $options .= $self -> {"template"} -> load_template("feature/news/controls/delete_${candelete}.tem", {"***postid***" => $post -> {"id"}});

    return $self -> {"template"} -> load_template("feature/news/controls.tem", {"***controls***" => $options});
}


## @method private $ _build_post($post, $temcache)
# Generate the body of a post to show in the news post list.
#
# @param post     A reference to a hash containing the post to generate.
# @param temcache A reference to a hash containing the templates used to generate
#                 the post block.
# @return A string containing the post HTML.
sub _build_post {
    my $self     = shift;
    my $post     = shift;
    my $temcache = shift;

    # Obtain the details of the poster and possible editor
    my $poster = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byid($post -> {"creator_id"});
    my $editor = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byid($post -> {"editor_id"});

    # Generate the body of the post
    my $content = $self -> {"template"} -> process_template($temcache -> {"contenttem"}, {"***message***" => $post -> {"message"}});

    # Determine whether the post has been edited
    my $editby = $self -> {"template"} -> process_template($temcache -> {"edittem"} -> [(($post -> {"creator_id"} != $post -> {"editor_id"}) ||
                                                                                         ($post -> {"created"} != $post -> {"edited"}))],
                                                           {"***edited***"   => $self -> {"template"} -> fancy_time($post -> {"edited"}),
                                                            "***posturl***"  => $self -> build_url(block => "news", params => { "postid" => $post -> {"id"}, "showhist" => "t" }),
                                                            "***profile***"  => $self -> build_url(block => "profile", pathinfo => [ $editor -> {"username"} ]),
                                                            "***name***"     => $editor -> {"fullname"},
                                                            "***gravhash***" => $editor -> {"gravatar_hash"},
                                                           });
    # And return the fillled-in post.
    return $self -> {"template"} -> process_template($temcache -> {"entrytem"},
                                                     {"***postid***"   => $post -> {"id"},
                                                      "***posted***"   => $self -> {"template"} -> fancy_time($post -> {"created"}),
                                                      "***posturl***"  => $self -> build_url(block => "news", params => { "postid" => $post -> {"id"} }),
                                                      "***profile***"  => $self -> build_url(block => "profile", pathinfo => [ $poster -> {"username"} ]),
                                                      "***name***"     => $poster -> {"fullname"},
                                                      "***gravhash***" => $poster -> {"gravatar_hash"},
                                                      "***title***"    => $post -> {"subject"},
                                                      "***content***"  => $content,
                                                      "***editby***"   => $editby,
                                                      "***controls***" => $self -> build_post_controls($post)});
}


## @method $ build_post_list($starid, $count, $show_fetchmore)
# Generate a list of posts to show in the news list.
#
# @param startid The ID of the post to start showing entries from. If
#                omitted, the first post is the latest one.
# @param count   The number of posts to retrieve. If omitted, the default set in
#                the Feature::News::post_count setting variable is used instead.
# @param show_fetchmore If set, and there are more than `count` posts left to
#                show, this will add the 'fetch more' button to the end of the
#                list.
# @return A string containing the list of news posts.
sub build_post_list {
    my $self    = shift;
    my $startid = shift;
    my $count   = shift || $self -> {"settings"} -> {"config"} -> {"Feature::News::post_count"};
    my $show_fetchmore = shift;

    # Fetch the list of posts. If the count is 1, only a single post is being shown, so there's no need to
    # determine whether there are more entries available even if show_fetchmore is set. If the count is
    # over 1, and show_fetchmore is set, fetch an extra post if possible, to determine whether there are
    # more posts to show.
    my $posts = $self -> {"news"} -> get_news_posts($self -> {"courseid"}, $startid, $count + ($count > 1 ? $show_fetchmore : 0))
        or $self -> {"logger"} -> die_log($self -> {"cgi"} -> remote_host(), "Unable to fetch news posts: ".$self -> {"news"} -> {"errstr"});

    my $temcache = {
        "entrytem"   => $self -> {"template"} -> load_template("feature/news/post.tem"),
        "contenttem" => $self -> {"template"} -> load_template("feature/news/post_content.tem"),
        "edittem"    => [
                          $self -> {"template"} -> load_template("feature/news/editby_disabled.tem"),
                          $self -> {"template"} -> load_template("feature/news/editby_enabled.tem")
                        ]
    };

    my $entry = 0;
    my $entrylist = "";

    foreach my $post (@{$posts}) {
        $entrylist .= $self -> _build_post($post, $temcache);
        last if(++$entry == $count);
    }

    $entrylist .= $self -> {"template"} -> load_template("feature/news/fetchmore.tem",
                                                         {"***url***" => $posts -> [$entry] -> {"id"}})
        if($show_fetchmore && scalar(@{$posts}) > $count);

    return $entrylist;
}


## @method @ build_news_list($error, $args)
# Build a list of news posts the user can see. If the user has create or edit
# access, this will also insert the appropriate html to allow them to create
# posts or edit old ones.
#
# @return An array containing two values: the page content (the news posts),
#         and a string to place in the page header to load any required
#         javascript.
sub build_news_list {
    my $self  = shift;
    my $error = shift;
    my $args  = shift;

    # Wrap the error message in a message box if we have one.
    $error = $self -> {"template"} -> load_template("feature/news/error_box.tem", {"***message***" => $error})
        if($error);

    # Has the user requested a specific post id to show?
    my $postid = is_defined_numeric($self -> {"cgi"}, "postid");

    # How many posts to show in the page?
    my $count  = $postid ? 1 : $self -> {"settings"} -> {"config"} -> {"Feature::News::post_count"};

    my $returntem  = $postid ? "returnlink.tem" : "noreturnlink.tem";
    my $returnlink = $self -> {"template"} -> load_template("feature/news/$returntem", {"***url***" => $self -> build_url(block => "news")});

    $self -> log("news:view", "Viewing $count posts from ".($postid ? "post $postid" : "latest"));

    return ($self -> {"template"} -> load_template("feature/news/postlist.tem",
                                                   {"***returnlink***" => $returnlink,
                                                    "***error***"      => $error,
                                                    "***entries***"    => $self -> build_post_list($postid, $count, 1),
                                                    "***postform***"   => $self -> build_newpost_form($args),
                                                   }),
            $self -> {"template"} -> load_template("feature/news/extrahead.tem"));
}


# ============================================================================
#  API Implementation

## @method $ build_api_more_response()
# Generate a string or hash that can be sent back to the user as an API response.
# This behaves much like build_news_list(), except that it treats a specified
# postid as the first post to return, and it will return up to Feature::News::post_count
# posts as part of the response, and include a 'fetch more' button if appropriate.
# The contents of the response may vary depending on whether the response succeeded.
#
# @return A string or hash containing the API response.
sub build_api_more_response {
    my $self = shift;
    my $posts;

    # Has the user requested a specific post id to show?
    my $postid = is_defined_numeric($self -> {"cgi"}, "postid");

    $self -> log("news:more", "Requested more from ".($postid ? "post $postid" : "latest"));

    # Try to build the post list, give up with an error if it doesn't work
    eval { $posts = $self -> build_post_list($postid, $self -> {"settings"} -> {"config"} -> {"Feature::News::post_count"}, 1) };
    return $self -> api_errorhash("list_failed", $@)
        if($@);

    return $posts;
}


## @method $ build_api_delete_response()
# Attempt to 'delete' (actually, mark as deleted) the post requested by the
# client. This will perform all normal permission checks and generate an XML
# API response hash to send to the client.
#
# @return A reference to a hash containing the API response data.
sub build_api_delete_response {
    my $self   = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    # Has a post been selected for deletion?
    my $postid = is_defined_numeric($self -> {"cgi"}, "postid")
        or return $self -> api_errorhash("no_postid", $self -> {"template"} -> replace_langvar("FEATURE_NEWS_APIDEL_NOPOST"));

    $self -> log("news:delete", "Requested delete of post $postid");

    # Get the post so it can be checked for access
    my $post = $self -> {"news"} -> get_post($postid)
        or return $self -> api_errorhash("bad_postid", $self -> {"template"} -> replace_langvar("FEATURE_NEWS_APIDEL_FAILED", {"***error***" => $self -> {"news"} -> {"errstr"}}));

    # Does the user have permission to delete it?
    my $ownership = ($post -> {"creator_id"} == $userid ? "own" : "other");
    if(!$self -> {"news"} -> check_permission($post -> {"metadata_id"}, $userid, "news.delete$ownership")) {
        $self -> log("error:news:delete", "Permission denied");
        return $self -> api_errorhash("perm_error", $self -> {"template"} -> replace_langvar("FEATURE_NEWS_APIDEL_PERM"))
    }

    # Get here and the post id is valid and the user can delete it, try it
    $self -> {"news"} -> delete_post($postid, $userid)
        or return $self -> api_errorhash("del_failed", $self -> {"template"} -> replace_langvar("FEATURE_NEWS_APIDEL_FAILED", {"***error***" => $self -> {"news"} -> {"errstr"}}));

    $self -> log("news:delete", "Post $postid deleted");

    return { 'response' => { 'status' => 'ok' } };
}


## @method $ build_api_edit_response()
# Generate a string or hash to return to the caller in response to an API edit
# request. This will edit the post, if the user has permission to do so, and
# it will send back the edited post text in the response.
#
# @return A string or hash containing the API response.
sub build_api_edit_response {
    my $self   = shift;
    my $userid = $self -> {"session"} -> get_session_userid();
    my $args   = {};

    # Has a post been selected for editing?
    my $postid = is_defined_numeric($self -> {"cgi"}, "postid")
        or return $self -> api_errorhash("no_postid", $self -> {"template"} -> replace_langvar("FEATURE_NEWS_APIEDIT_NOPOST"));

    $self -> log("news:edit", "Requested edit of post $postid");

    # Get the post so it can be checked for access
    my $post = $self -> {"news"} -> get_post($postid)
        or return $self -> api_errorhash("bad_postid", $self -> {"template"} -> replace_langvar("FEATURE_NEWS_APIEDIT_FAILED", {"***error***" => $self -> {"news"} -> {"errstr"}}));

    # Does the user have permission to edit it?
    my $ownership = ($post -> {"creator_id"} == $userid ? "own" : "other");
    if(!$self -> {"news"} -> check_permission($post -> {"metadata_id"}, $userid, "news.edit$ownership")) {
        $self -> log("error:news:edit", "Permission denied");
        return $self -> api_errorhash("perm_error", $self -> {"template"} -> replace_langvar("FEATURE_NEWS_APIEDIT_PERM"))
    }

    # User has permission, check the fields
    my $errors = $self -> _validate_fields($args);

    return $self -> api_errorhash("bad_values", $self -> {"template"} -> load_template("error_list.tem",
                                                                                       {"***message***" => "{L_FEATURE_NEWS_ERR_POSTFAIL}",
                                                                                        "***errors***"  => $errors}))
        if($errors);

    # Edit the post...
    if($self -> {"news"} -> edit_post($postid, $userid, $args -> {"subject"}, $args -> {"message"})) {
        $post = $self -> {"news"} -> get_post($postid)
            or return $self -> api_errorhash("bad_postid", $self -> {"template"} -> replace_langvar("FEATURE_NEWS_APIEDIT_FAILED", {"***error***" => $self -> {"news"} -> {"errstr"}}));

        $self -> log("news:edit", "Post $postid edited");

        return $self -> _build_post($post, { "entrytem"   => $self -> {"template"} -> load_template("feature/news/post.tem"),
                                             "contenttem" => $self -> {"template"} -> load_template("feature/news/post_content.tem"),
                                             "edittem"    => [
                                                 $self -> {"template"} -> load_template("feature/news/editby_disabled.tem"),
                                                 $self -> {"template"} -> load_template("feature/news/editby_enabled.tem")
                                                 ]
                                    });
    } else {
        return $self -> api_errorhash("bad_values", $self -> {"template"} -> load_template("error_list.tem",
                                                                                           {"***message***" => "{L_FEATURE_NEWS_ERR_POSTFAIL}",
                                                                                            "***errors***"  => $self -> {"news"} -> {"errstr"}}));
    }

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
    my ($content, $extrahead);

    # Confirm that the user is logged in and has access to the course
    # ALL FEATURES SHOULD DO THIS BEFORE DOING ANYTHING ELSE!!
    my $error = $self -> check_login_courseview(0);
    return $error if($error);

    # Is this an API call, or a normal news page call?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {
        if($apiop eq "more") {
            return $self -> api_html_response($self -> build_api_more_response());
        } elsif($apiop eq "delete") {
            return $self -> api_response($self -> build_api_delete_response());
        } elsif($apiop eq "edit") {
            return $self -> api_html_response($self -> build_api_edit_response());
        } else {
            return $self -> api_html_response($self -> api_errorhash('bad_op',
                                                                     $self -> {"template"} -> replace_langvar("API_BAD_OP")))
        }
    } else {

        # Is the user attempting to post a new news post? If so, they need permission
        # and validation. Of the form submission, the user probably doesn't need validation.
        if(defined($self -> {"cgi"} -> param("newpost"))) {
            my ($error, $args) = $self -> validate_news_post();
            ($content, $extrahead) = $self -> build_news_list($error, $args);

        } else {
            # Generate the news list
            ($content, $extrahead) = $self -> build_news_list();
        }

        # User has access, generate the news page for the course.
        return $self -> generate_course_page("{L_FEATURE_NEWS_TITLE}", $content, $extrahead);
    }
}

1;
