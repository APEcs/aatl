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
                                            roles    => $self -> {"system"} -> {"roles"})
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
#  News posts

## @method $ build_newpost_form()
# Determine whether the user has access to post new news entries, and if the
# user does generate the appropriate chunk of HTML.
#
# @return The HTML to place in the new post form area
sub build_newpost_form {
    my $self = shift;

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

    return ($self -> {"template"} -> load_template("feature/news/postform_".($canpost ? "enabled" : "disabled").".tem"));
}


## @method $ build_post_list($starid, $count, $show_fetchmore)
# Generate a list of posts to show in the news list.
sub build_post_list {
    my $self    = shift;
    my $startid = shift;
    my $count   = shift;
    my $show_fetchmore = shift;

    # Fetch the list of posts. If the count is 1, only a single post is being shown, so there's no need to
    # determine whether there are more entries available even if show_fetchmore is set. If the count is
    # over 1, and show_fetchmore is set, fetch an extra post if possible, to determine whether there are
    # more posts to show.
    my $posts = $self -> {"news"} -> get_news_posts($self -> {"courseid"}, $startid, $count + ($count > 1 ? $show_fetchmore : 0))
        or $self -> {"logger"} -> die_log($self -> {"cgi"} -> remote_host(), "Unable to fetch news posts: ".$self -> {"news"} -> {"errstr"});

    return "";
}


## @method @ build_news_list()
# Build a list of news posts the user can see. If the user has create or edit
# access, this will also insert the appropriate html to allow them to create
# posts or edit old ones.
#
# @return An array containing two values: the page content (the news posts),
#         and a string to place in the page header to load any required
#         javascript.
sub build_news_list {
    my $self = shift;

    # Has the user requested a specific post id to show?
    my $postid = is_defined_numeric($self -> {"cgi"}, "postid");

    # How many posts to show in the page?
    my $count  = $postid ? 1 : $self -> {"settings"} -> {"config"} -> {"Feature::News::post_count"};

    my $returntem  = $postid ? "returnlink.tem" : "noreturnlink.tem";
    my $returnlink = $self -> {"template"} -> load_template("feature/news/$returntem", {"***url***" => $self -> build_url(block => "news")});

    return ($self -> {"template"} -> load_template("feature/news/postlist.tem",
                                                   {"***returnlink***" => $returnlink,
                                                    "***entries***"    => $self -> build_post_list($postid, $count, 1),
                                                    "***postform***"   => $self -> build_newpost_form(),
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

    # Confirm that the user is logged in and has access to the course
    # ALL FEATURES SHOULD DO THIS BEFORE DOING ANYTHING ELSE!!
    my $error = $self -> check_login_courseview(0);
    return $error if($error);

    # Is this an API call, or a normal news page call?
    my $apiop = $self -> api_operation();
    if(defined($apiop)) {

    } else {
        # Generate the next list
        my ($content, $extrahead) = $self -> build_news_list();

        # User has access, generate the news page for the course.
        return $self -> generate_course_page("{L_FEATURE_NEWS_TITLE}", $content, $extrahead);
    }
}

1;
