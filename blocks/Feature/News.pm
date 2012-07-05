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
use Data::Dumper;

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

    # Cache the courseid for later
    $self -> {"courseid"} = $self -> determine_courseid();

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

    return { "news.post"      => $self -> {"template"} -> replace_langvar("CAPABILITY_NEWS.POST"),
             "news.editown"   => $self -> {"template"} -> replace_langvar("CAPABILITY_NEWS.EDITOWN"),
             "news.editother" => $self -> {"template"} -> replace_langvar("CAPABILITY_NEWS.EDITOTHER"),
           };
}


# ============================================================================
#  Validation

## @method @ validate_news_post()
# Determine whether the user has permission to post news posts, and if they do
# validate the data they have submitted.
#
# @return An array of two values: a reference to the new post data on success,
#         an error message on failure; and a reference to a hash containing any
#         submitted values that passed validation.
sub validate_news_post {
    my $self = shift;
    my ($args, $errors, $error) = ({}, "", "");

    my $errtem = $self -> {"template"} -> load_template("error_item.tem");

    # Exit with a permission error unless the user has permission to post
    my $canpost = $self -> {"news"} -> check_permission($self -> {"system"} -> {"courses"} -> get_course_metadataid($self -> {"courseid"}),
                                                        $self -> {"session"} -> get_session_userid(),
                                                        "news.post",
                                                        undef);
    return ($self -> {"template"} -> load_template("error_list.tem",
                                                   {"***message***" => "{L_FEATURE_NEWS_ERR_POSTFAIL}",
                                                    "***errors***"  => $self -> {"template"} -> process_template($errtem,
                                                                                                                 {"***error***" => "{L_FEATURE_NEWS_ERR_POSTPERM}"})}),
            $args) unless($canpost);

    # User has post permission, have they filled in the form correctly?
    ($args -> {"subject"}, $error) = $self -> validate_string("subject", {"required" => 1,
                                                                          "nicename" => $self -> {"template"} -> replace_langvar("FEATURE_NEWS_SUBJECT"),
                                                                          "minlen"   => 1,
                                                                          "maxlen"   => 255});
    $errors .= $self -> {"template"} -> process_template($errtem, {"***error***" => $error}) if($error);

    ($args -> {"message"}, $error) = $self -> validate_htmlarea("message", {"required" => 1,
                                                                            "validate" => $self -> {"config"} -> {"Core:validate_htmlarea"}});
    $errors .= $self -> {"template"} -> process_template($errtem, {"***error***" => $error}) if($error);

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

    return ($post, $args);
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
                                                        "news.post",
                                                        undef);
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

    my $entrytem   = $self -> {"template"} -> load_template("feature/news/post.tem");
    my $contenttem = $self -> {"template"} -> load_template("feature/news/post_content.tem");
    my $entry = 0;
    my $entrylist = "";

    foreach my $post (@{$posts}) {
        # Obtain the details of the poster and possible editor
        my $poster = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byid($post -> {"creator_id"});
        my $editor = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byid($post -> {"author_id"});

        # Generate the body of the post
        my $content = $self -> {"template"} -> process_template($contenttem, {"***message***" => $post -> {"message"}});

        # And append the whole post to the list of posts.
        $entrylist .= $self -> {"template"} -> process_template($entrytem, {"***posted***"   => $self -> {"template"} -> format_time($post -> {"created"}),
                                                                            "***posturl***"  => $self -> build_url(block => "news", params => { "postid" => $post -> {"id"} }),
                                                                            "***profile***"  => $self -> build_url(block => "profile", pathinfo => [ $poster -> {"username"} ]),
                                                                            "***name***"     => $poster -> {"fullname"},
                                                                            "***gravhash***" => $poster -> {"gravatar_hash"},
                                                                            "***title***"    => $post -> {"subject"},
                                                                            "***content***"  => $content });
        last if(++$entry == $count);
    }

    $entrylist .= $self -> {"template"} -> load_template("feature/news/fetchmore.tem",
                                                         {"***url****" => $self -> build_url(pathinfo => [ "api", "more" ],
                                                                                             paramstr => "postid=".$posts -> [$entry] -> {"id"})})
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

    return ($self -> {"template"} -> load_template("feature/news/postlist.tem",
                                                   {"***returnlink***" => $returnlink,
                                                    "***error***"      => $error,
                                                    "***entries***"    => $self -> build_post_list($postid, $count, 1),
                                                    "***postform***"   => $self -> build_newpost_form($args),
                                                   }),
            $self -> {"template"} -> load_template("feature/news/extrahead.tem"));
}


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
    if(defined($apiop) && $apiop eq "more") {
#        $self -> api_response($self -> build_api_response(),
#                              "KeepRoot" => 1,
#                             );
    } else {
        # Is the user attempting to post a new news post? If so, they need permission
        # and validation. Of the form submission, the user probably doesn't need validation.
        if(defined($self -> {"cgi"} -> param("newpost"))) {
            my ($error, $args) = $self -> validate_news_post();

            # Has an error been encountered while generating the news post? If so,
            # send everything back with the error message...
            if(!ref($error)) {
                ($content, $extrahead) = $self -> build_news_list($error, $args);

            # Otherwise, send back the new page.
            } else {
                ($content, $extrahead) = $self -> build_news_list();
            }
        } else {
            # Generate the news list
            ($content, $extrahead) = $self -> build_news_list();
        }

        # User has access, generate the news page for the course.
        return $self -> generate_course_page("{L_FEATURE_NEWS_TITLE}", $content, $extrahead);
    }
}

1;
