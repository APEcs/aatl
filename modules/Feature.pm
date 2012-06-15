## @file
# This file contains the implementation of the AATL Feature base class.
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

## @class Feature
#
package Feature;

use strict;
use base qw(Block); # Features are just a specific form of Block
use CGI::Util qw(escape);
use Utils qw(is_defined_numeric path_join);

## @method $ determine_courseid()
# Attempt to work out which course the user is actually looking at. This is not
# entirely straightforward, as the user may be looking at /comp101 but wants
# to look at an old one, or only has access to an old one.
#
# @return The ID of the course the user is looking at, 0 if the user is not
#         looking at a course, or undef on failure.
sub determine_courseid {
    my $self = shift;

    $self -> clear_error();

    # Always has to be a course specified, or nothing can be done
    my $course = $self -> {"cgi"} -> param("course");
    return 0 if(!$course);
    # NOTE: the lack of course **does not** clear the session cid. This might, perhaps,
    # help somewhat with browser history issues (although they're likely to be the source
    # of considerable woe, if a user moves from one course to another through the history)

    my $cid = is_defined_numeric($self -> {"cgi"}, "cid");

    # If a cid is specified, it should override any cid set in the user's session,
    # provided that it is a valid cid. Note that this will not actually check the
    # user has access to the course, just that it is a valid selection
    if($cid) {
        my $coursedata = $self -> {"system"} -> {"courses"} -> _fetch_course($cid);
        return undef if(!defined($coursedata));
        return $self -> self_error("Request for non-existent course $cid.") if(!$coursedata);

        # Does the course match the set course code?
        return $self -> self_error("Request for course $cid that does not match current course path.")
            unless($course eq $coursedata -> {"code"});

        # cid is valid, and course codes match, update the user's current cid
        # and let the caller check permissions on it
        $self -> {"session"} -> set_variable("cid-$course", $cid);
        return $cid;
    }

    # No courseid has been provided, if the user has a cid set, does the current
    # course path match? If so, the user is looking at a known version of a course.
    $cid = $self -> {"session"} -> get_variable("cid-$course");
    if($cid) {
        my $coursedata = $self -> {"system"} -> {"courses"} -> _fetch_course($cid);
        return undef if(!defined($coursedata));
        return $self -> self_error("Request for non-existent course $cid.") if(!$coursedata);

        # If the course path matches the code, the user is looking at a known course
        return $cid if($course eq $coursedata -> {"code"});

        # Otherwise, the user is looking at a course other than the one set in their cid,
        # so clear the cid and let the system work out the correct one...
        $cid = undef;
    }

    # Get here and, if there's no cid specified in either the query string or session
    # (or the cid in the session doesn't match the current course path).
    # This means the system needs to work out which course the user is actually looking at,
    # which generally means the latest run of the course the user has access to, or the
    # latest run id anyway.

    # Get a list of course entries whose code matches the course selected
    my $courses = $self -> {"system"} -> {"courses"} -> get_courses($course);
    return undef if(!defined($courses));

    # Empty list here means that the course code is invalid (no courses exist with that code)
    return $self -> self_error("Request for non-existent course code.") unless(scalar(@{$courses}));

    # Now traverse the list of codes, looking for one the user has access to. The first one
    # encountered will be the most recent one.
    my $userid = $self -> {"session"} -> get_session_userid();
    foreach $cid (@{$courses}) {
        if($self -> {"system"} -> {"courses"} -> check_permission($course, $userid, "course.view")) {
            $self -> {"session"} -> set_variable("cid-$course", $cid);
            return $cid;
        }
    }

    # Otherwise, give up and set the cid to the first in the list. This will give a permission
    # error, but that's about all that can be done in this situation.
    $self -> {"session"} -> set_variable("cid-$course", $courses -> [0]);
    return $courses -> [0];
}


## @method @ check_login_courseview($allow_nocourse)
# Determine whether the current user, as specified in the session, is logged
# in and has access to the course specified in the query string.
#
# @param allow_nocourse If true, the checks for course access are skipped if
#                       no course is specified in the query string. Otherwise,
#                       course checks are enforced.
# @return undef if the user is logged in and has access, otherwise a page to
#         send back with a permission error. If the user is not logged in,
#         this will silently redirect the user to a login form.
sub check_login_courseview {
    my $self           = shift;
    my $allow_nocourse = shift;

    # Anonymous users need to get punted over to the login form
    if($self -> {"session"} -> anonymous_session()) {
        print STDERR "Detected anonymous session, redirecting to login\n";

        print $self -> {"cgi"} -> redirect($self -> build_login_url());
        exit;

    # Otherwise, permissions need to be checked
    } else {
        my ($title, $message);

        my $course = $self -> determine_courseid();
        if($course) {
            # If the user has permission to view the course, return the 'all is okay' result
            if($self -> {"system"} -> {"courses"} -> check_permission($course, $self -> {"session"} -> get_session_userid(), "course.view")) {
                return undef;
            } else {
                # Logged in, but permission failed
                $title   = $self -> {"template"} -> replace_langvar("FEATURE_ERR_COURSE_NOACCESS_TITLE");
                $message = $self -> {"template"} -> message_box("{L_FEATURE_ERR_COURSE_NOACCESS_TITLE}",
                                                                "permission_error",
                                                                "{L_FEATURE_ERR_COURSE_NOACCESS_SUMAMRY}",
                                                                "{L_FEATURE_ERR_COURSE_NOACCESS_DESC}");
            }
        # If no course is specified, but that's allowed, return an okay result
        } elsif($allow_nocourse) {
            return undef;

        # If no course is specified, and one is needed, complain
        } else {
            $title   = $self -> {"template"} -> replace_langvar("FEATURE_ERR_NOCOURSE_TITLE");
            $message = $self -> {"template"} -> message_box("{L_FEATURE_ERR_NOCOURSE_TITLE}",
                                                            "error",
                                                            "{L_FEATURE_ERR_NOCOURSE_SUMAMRY}",
                                                            "{L_FEATURE_ERR_NOCOURSE_DESC}");
        }

        # Build the error page...
        return $self -> {"template"} -> load_template("error_page.tem",
                                                      {"***title***"   => $title,
                                                       "***message***" => $message,
                                                       "***toolbar***" => $self -> {"system"} -> {"toolbar"} -> build(),
                                                      });
    }
}


## @method $ build_login_url()
# Attempt to generate a URL that can be used to redirect the user to a login form.
# The user's current query state (course, block, etc) is stored in a session variable
# that can later be used to bring them back to the location this was called from.
#
# @return A relative login form redirection URL.
sub build_login_url {
    my $self = shift;

    # Note: CGI::query_string() produces a properly escaped, joined query string based on the
    #       **current parameters**, even ones added by the program (hence the course and block
    #       parameters added by the BlockSelector will be included!)
    $self -> {"session"} -> set_variable("savestate", $self -> {"cgi"} -> query_string());

    return $self -> build_url("course" => ($self -> {"cgi"} -> param("course") || $self -> {"settings"} -> {"config"} -> {"aatlcourse_name"}),
                              "block"  => "login");
}


## @method $ get_saved_state()
# A convenience wrapper around Session::get_variable() for fetching the state saved in
# build_login_url().
#
# @return A string containing saved query string state, or an empty string.
sub get_saved_state {
    my $self = shift;

    return $self -> {"session"} -> get_variable("savestate") || "";
}


## @method $ build_return_url($fullurl)
# Pulls the data out of the session saved state, checks it for safety,
# and returns the URL the user should be redirected/linked to to return to the
# location they were attempting to access before login.
#
# @param fullurl If set to true, the generated url will contain the protocol and
#                host. Otherwise the URL will be absolute from the server root.
# @return A relative return URL.
sub build_return_url {
    my $self    = shift;
    my $fullurl = shift;

    # Get the saved state
    my $state = $self -> get_saved_state();

    # fall over on a default if it's not available, or it contains illegal characters
    return $self -> build_url("course" => $self -> {"cgi"} -> param("course"),
                              "block"  => $self -> {"cgi"} -> param("block"))
        unless($state && $state =~ /^([&;+=a-zA-Z0-9_.~-]|%[a-fA-F0-9]{2,})+$/);

    # Pull out the course and block
    my ($course) = $state =~ /course=(\w+)/;
    my ($block)  = $state =~ /block=(\w+)/;

    # return url block should never be "login"
    $block = "" if($block eq "login");

    # Build the URL from them
    return $self -> build_url("course"   => $course,
                              "block"    => $block,
                              "paramstr" => $state);
}


## @method $ build_url(%args)
# Build a url suitable for use at any point in the system. This takes the args
# and attempts to build a url from them. Supported arguments are:
#
# * fullurl  - if set, the resulting URL will include the protocol and host. Defaults to
#              false (URL is absolute from the host root).
# * course   - the course code to include in the url. If not specified, the current
#              course is used instead. If there is no course, and any other args are
#              specified, this is set to the value set for 'aatlcourse_name' in the
#              configuration.
# * block    - the name of the block to include in the url.
# * cid      - the course id to use. If this is not specified, the current cid is used
#              instead. If no cid is set, no cid is included in the url.
# * params   - a reference to a hash of additional query string arguments. Values may
#              be references to arrays, in which case multiple copies of the parameter
#              are added to the query string.
# * paramstr - An optional, previously-escaped, well formed query string fragment to
#              append to the query string.
#
# @param args A hash of arguments to use when building the URL.
# @return A string containing the URL.
sub build_url {
    my $self = shift;
    my %args = @_;
    my $base = "";

    # start off with the protocol and host:port if needed.

    # Fix up the course and cid
    $args{"course"} = $self -> {"cgi"} -> param("course") || $self -> {"settings"} -> {"config"} -> {"aatlcourse_name"}
        unless($args{"course"});

    $args{"cid"}    = $self -> {"cgi"} -> param("cid")
        unless($args{"cid"});

    my @pairs;
    # make sure the cid is first in the query strint, if set.
    push(@pairs, "cid=$args{cid}") if($args{"cid"});

    # build the parameter list
    if($args{"params"}) {
        foreach my $param (keys(%{$args{"params"}})) {
            for my $value ($args{"params"} -> {$param}) {
                next unless(defined($value)); # Ignore parameters with no defined values

                push(@pairs, escape($param)."=".escape($value));
            }
        }
    }
    push(@pairs, $args{"paramstr"}) if($args{"paramstr"});

    # And squish into a query string
    my $querystring = join("&", @pairs);

    # building time...
    my $url = "";
    if($args{"fullurl"}) {
        $url = path_join($self -> {"cgi"} -> url(-base => 1), $self -> {"settings"} -> {"config"} -> {"scriptpath"}, $args{"course"}, $args{"block"});
    } else {
        $url = path_join($self -> {"settings"} -> {"config"} -> {"scriptpath"}, $args{"course"}, $args{"block"});
    }

    $url .= "?$querystring" if($querystring);

    return $url;
}

1;
