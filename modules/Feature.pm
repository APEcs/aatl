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
use XML::Simple;

# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Overloaded constructor for Features.
#
# @param args A hash of values to initialise the object with. See the Block docs
#             for more information.
# @return A reference to a new Feature object on success, undef on error.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_)
        or return undef;

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

    return { # No capabilities used by this feature
           };
}


# ============================================================================
#  Course convenience functions

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
        return $self -> self_error("Request for course $cid that does not match current course path ($course v ".$coursedata -> {"code"}.").")
            unless(lc($course) eq lc($coursedata -> {"code"}));

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
        return $cid if(lc($course) eq lc($coursedata -> {"code"}));

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
        print $self -> {"cgi"} -> redirect($self -> build_login_url());
        exit;

    # Otherwise, permissions need to be checked
    } else {
        my ($title, $message);

        my $course = $self -> {"courseid"};
        if($course) {
            # If the user has permission to view the course, return the 'all is okay' result
            if($self -> {"system"} -> {"courses"} -> check_permission($course, $self -> {"session"} -> get_session_userid(), "course.view")) {
                return undef;
            } else {
                $self -> log("error:permission", "User does not have access to course");

                # Logged in, but permission failed
                $title   = $self -> {"template"} -> replace_langvar("FEATURE_ERR_COURSE_NOACCESS_TITLE");
                $message = $self -> {"template"} -> message_box("{L_FEATURE_ERR_COURSE_NOACCESS_TITLE}",
                                                                "permission_error",
                                                                "{L_FEATURE_ERR_COURSE_NOACCESS_SUMMARY}",
                                                                "{L_FEATURE_ERR_COURSE_NOACCESS_DESC}",
                                                                undef,
                                                                "errorcore",
                                                                [ {"message" => $self -> {"template"} -> replace_langvar("SITE_CONTINUE"),
                                                                   "colour"  => "blue",
                                                                   "action"  => "location.href='{V_[scriptpath]}'"} ]);

            }
        # If no course is specified, but that's allowed, return an okay result
        } elsif($allow_nocourse) {
            return undef;

        # If no course is specified, and one is needed, complain
        } else {
            $self -> log("error:noourse", "User has attempted to access a course with no id");

            $title   = $self -> {"template"} -> replace_langvar("FEATURE_ERR_NOCOURSE_TITLE");
            $message = $self -> {"template"} -> message_box("{L_FEATURE_ERR_NOCOURSE_TITLE}",
                                                            "error",
                                                            "{L_FEATURE_ERR_NOCOURSE_SUMMARY}",
                                                            "{L_FEATURE_ERR_NOCOURSE_DESC}",
                                                            undef,
                                                            "errorcore",
                                                            [ {"message" => $self -> {"template"} -> replace_langvar("SITE_CONTINUE"),
                                                               "colour"  => "blue",
                                                               "action"  => "location.href='{V_[scriptpath]}'"} ]);
        }

        my $userbar = $self -> {"module"} -> load_module("Feature::Userbar");

        # Build the error page...
        return $self -> {"template"} -> load_template("error/general.tem",
                                                      {"***title***"     => $title,
                                                       "***message***"   => $message,
                                                       "***extrahead***" => "",
                                                       "***userbar***"   => $userbar -> block_display(),
                                                      });
    }
}


# ============================================================================
#  View related - course page wrapping, etc.

## @method $ generate_course_page($title, $content, $extrahead)
# A convenience function to wrap page content in a course page. This function allows
# features to embed their content in a course page without having to build the whole
# page themselves. It should be called to wrap the content when the feature's
# page_display is returning.
#
# @param title     The page title.
# @param content   The content to show in the page.
# @param extrahead Any extra directives to place in the header.
# @return A string containing the course page.
sub generate_course_page {
    my $self      = shift;
    my $title     = shift;
    my $content   = shift;
    my $extrahead = shift || "";

    my $courseid = $self -> {"courseid"}
        or return $self -> self_error("Unable to determine course id.");

    # Fetch the current course
    my $course = $self -> {"system"} -> {"courses"} -> _fetch_course($courseid)
        or return $self -> self_error("Unable to obtain course for cid $courseid");

    my $userbar = $self -> {"module"} -> load_module("Feature::Userbar");

    my $rightboxes = "";
    # If the current feature can build rightboxes, do so.
    $rightboxes = $self -> build_rightboxes() if($self -> can("build_rightboxes"));

    # Build the feature links and custom background list
    my $features = $self -> {"system"} -> {"courses"} -> _fetch_set_features($courseid, "sidebar");
    my $featurelist = "";
    my $menubgs     = "";
    my $entrytem    = $self -> {"template"} -> load_template("course/menu_entry.tem");
    my $bgtem       = $self -> {"template"} -> load_template("course/menu_bg.tem");
    foreach my $feature (@{$features}) {
        $featurelist .= $self -> {"template"} -> process_template($entrytem, {"***url***"    => $self -> build_url(block => $feature -> {"block_name"}, pathinfo => "none"),
                                                                              "***name***"   => $feature -> {"block_name"},
                                                                              "***title***"  => $feature -> {"title"},
                                                                              "***active***" => $self -> {"block"} eq $feature -> {"block_name"} ? "menu-active" : ""});
        $menubgs .= $self -> {"template"} -> process_template($bgtem, {"***background***" => $feature -> {"background-image"}})
            if($feature -> {"background-image"});
    }

    $extrahead .= $self -> {"template"} -> load_template("course/menubgs.tem", { "***menubgs***" => $menubgs});

    return $self -> {"template"} -> load_template("course/page.tem", {"***extrahead***"    => $extrahead,
                                                                      "***title***"        => $title,
                                                                      "***coursecode***"   => $course -> {"code"},
                                                                      "***courseid***"     => $self -> {"courseid"},
                                                                      "***coursetitle***"  => $course -> {"title"},
                                                                      "***featurelinks***" => $featurelist,
                                                                      "***rightboxes***"   => $rightboxes,
                                                                      "***rightspace***"   => $rightboxes ? "rightspace" : "",
                                                                      "***content***"      => $content,
                                                                      "***userbar***"      => $userbar -> block_display()
                                                  });
}


# ============================================================================
#  URL building

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
    my ($course, $block);

    # Get the saved state
    my $state = $self -> get_saved_state();

    if($state && $state =~ /^([&;+=a-zA-Z0-9_.~-]|%[a-fA-F0-9]{2,})+$/) {
        # Pull out the course and block
        ($course) = $state =~ /course=(\w+)/;
        ($block)  = $state =~ /block=(\w+)/;
    } else {
        # fall back on the current
        $course = $self -> {"cgi"} -> param("course");
        $block  = $self -> {"cgi"} -> param("block");
    }

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
# * pathinfo - either a string containing pathinfo to append to the course/block, or
#              a reference to an array of pathinfo fragments to join and append. If this
#              is set to "none", no pathinfo will be appended at all.
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

    # Fix up the course and cid
    $args{"course"} = $self -> {"cgi"} -> param("course") || $self -> {"settings"} -> {"config"} -> {"aatlcourse_name"}
        unless($args{"course"});

    $args{"cid"}    = $self -> {"cgi"} -> param("cid")
        unless($args{"cid"});

    # Work out any additional pathinfo
    my @parampath = $self -> {"cgi"} -> param("pathinfo");
    if($args{"pathinfo"} && $args{"pathinfo"} ne "none") {
        # If the user-supplied pathinfo is a reference to an array, join it into a string.
        $args{"pathinfo"} = join("/", @{$args{"pathinfo"}}) if(ref($args{"pathinfo"}) eq "ARRAY");
        # If there is no user-supplied pathinfo, try building it from the stored pathinfo
        $args{"pathinfo"} = join("/", @parampath) unless($args{"pathinfo"});
    } else {
        $args{"pathinfo"} = undef;
    }

    my @pairs;
    # make sure the cid is first in the query strint, if set.
    push(@pairs, "cid=$args{cid}") if($args{"cid"});

    # build the parameter list
    if($args{"params"}) {
        foreach my $param (keys(%{$args{"params"}})) {
            # Do not include the course, block, or pathinfo in the query string components
            next if($param eq "course" || $param eq "block" || $param eq "pathinfo");

            for my $value ($args{"params"} -> {$param}) {
                next unless(defined($value)); # Ignore parameters with no defined values
                push(@pairs, escape($param)."=".escape($value));
            }
        }
    }
    push(@pairs, $args{"paramstr"}) if($args{"paramstr"});

    # And squish into a query string
    my $querystring = join("&amp;", @pairs);

    # building time...
    my $url = "";
    if($args{"fullurl"}) {
        $url = path_join($self -> {"cgi"} -> url(-base => 1), $self -> {"settings"} -> {"config"} -> {"scriptpath"}, $args{"course"}, $args{"block"}, $args{"pathinfo"});
    } else {
        $url = path_join($self -> {"settings"} -> {"config"} -> {"scriptpath"}, $args{"course"}, $args{"block"}, $args{"pathinfo"});
    }

    # strip course and block from the query string if they've somehow made it in there
    # note this can't simply be made 'eg' as the progressive match can leave a trailing &
    while($querystring =~ s{(&?)(?:course|block)=[^&]+(&?)}{$1 && $2 ? "&" : ""}e) {}

    $url .= "?$querystring" if($querystring);

    return $url;
}


# ============================================================================
#  API support

## @method $ is_api_operation()
# Determine whether the feature is being called in API mode, and if so what operation
# is being requested.
#
# @return A string containing the API operation name if the script is being invoked
#         in API mode, undef otherwise. Note that, if the script is invoked in API mode,
#         but no operation has been specified, this returns an empty string.
sub is_api_operation {
    my $self = shift;

    # API stuff is encoded in the pathinfo
    my @pathinfo = $self -> {"cgi"} -> param('pathinfo');

    # No pathinfo means no API mode.
    return undef unless(scalar(@pathinfo));

    # API mode is set by placing 'api' in the first pathinfo entry. The second pathinfo
    # entry is the operation.
    return $pathinfo[1] || "" if($pathinfo[0] eq 'api');

    return undef;
}


## @method $ api_errorhash($code, $message)
# Generate a hash that can be passed to api_response() to indicate that an error was encountered.
#
# @param code    A 'code' to identify the error. Does not need to be numeric, but it
#                should be short, and as unique as possible to the error.
# @param message The human-readable error message.
# @return A reference to a hash to pass to api_response()
sub api_errorhash {
    my $self    = shift;
    my $code    = shift;
    my $message = shift;

    return { 'error' => {
                          'info' => $message,
                          'code' => $code
                        }
           };
}


## @method $ api_html_response($data)
# Generate a HTML response containing the specified data.
#
# @param data The data to send back to the client. If this is a hash, it is
#             assumed to be the result of a call to api_errorhash() and it is
#             converted to an appropriate error box. Otherwise, the data is
#             wrapped in a minimal html wrapper for return to the client.
# @return The html response to send back to the client.
sub api_html_response {
    my $self = shift;
    my $data = shift;

    # Fix up error hash returns
    $data = $self -> {"template"} -> load_template("api/html_error.tem", {"***code***" => $data -> {"error"} -> {"code"},
                                                                          "***info***" => $data -> {"error"} -> {"info"}})
        if(ref($data) eq "HASH" && $data -> {"error"});

    return $self -> {"template"} -> load_template("api/html_wrapper.tem", {"***data***" => $data});
}


## @method $ api_response($data, %xmlopts)
# Generate an XML response containing the specified data. This function will not return
# if it is successful - it will return an XML response and exit.
#
# @param data    A reference to a hash containing the data to send back to the client as an
#                XML response.
# @param xmlopts Options passed to XML::Simple::XMLout. Note that the following defaults are
#                set for you:
#                - XMLDecl is set to '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>'
#                - KeepRoot is set to 0
#                - RootName is set to 'api'
# @return Does not return if successful, otherwise returns undef.
sub api_response {
    my $self    = shift;
    my $data    = shift;
    my %xmlopts = @_;
    my $xmldata;

    $xmlopts{"XMLDecl"} = '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>'
        unless(defined($xmlopts{"XMLDecl"}));

    $xmlopts{"KeepRoot"} = 0
        unless(defined($xmlopts{"KeepRoot"}));

    $xmlopts{"RootName"} = 'api'
        unless(defined($xmlopts{"RootName"}));

    eval { $xmldata = XMLout($data, %xmlopts); };
    $xmldata = $self -> {"template"} -> load_template("xml/error_response.tem", { "***code***"  => "encoding_failed",
                                                                                  "***error***" => "Error encoding XML response: $@"})
        if($@);

    print $self -> {"cgi"} -> header(-type => 'application/xml',
                                     -charset => 'utf-8');
    print Encode::encode_utf8($xmldata);

    $self -> {"template"} -> set_module_obj(undef);
    $self -> {"messages"} -> set_module_obj(undef);
    $self -> {"system"} -> clear() if($self -> {"system"});
    $self -> {"session"} -> {"auth"} -> {"app"} -> set_system(undef) if($self -> {"session"} -> {"auth"} -> {"app"});

    $self -> {"dbh"} -> disconnect();
    $self -> {"logger"} -> end_log();

    exit;
}


# ============================================================================
#  General utility

## @method void log($type, $message)
# Log the current user's actions in the system. This is a convenience wrapper around the
# Logger::log function.
#
# @param type     The type of log entry to make, may be up to 64 characters long.
# @param message  The message to attach to the log entry, avoid messages over 128 characters.
sub log {
    my $self     = shift;
    my $type     = shift;
    my $message  = shift;

    $message = "[Course:".($self -> {"courseid"} ? $self -> {"courseid"} : "none")."] $message";
    $self -> {"logger"} -> log($type, $self -> {"session"} -> get_session_userid(), $self -> {"cgi"} -> remote_host(), $message);
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


## @method $ tab_bar($tabs, $hascontents)
# Generate a tab bar to show on a page. This takes a reference to an array of tabs, and
# generates a html block containing the tab bar.
#
# @param tabs        A reference to an array of hashrefs, each entry should contain the keys
#                    'url', 'text', 'title', and optionally 'active' for active tabs.
# @param hascontents If true, the tab is assumed to be connected to a larger display block.
# @return A string containing the tab bar html.
sub tab_bar {
    my $self        = shift;
    my $tabs        = shift;
    my $hascontents = shift;

    my $opttem = $self -> {"template"} -> load_template("tabs/option.tem");
    my $options = "";
    foreach my $opt (@{$tabs}) {
        next unless($opt -> {"visible"});

        $options .= $self -> {"template"} -> process_template($opttem, {"***url***"    => $opt -> {"url"},
                                                                        "***text***"   => $opt -> {"text"},
                                                                        "***title***"  => $opt -> {"title"},
                                                                        "***active***" => $opt -> {"active"} ? " active" : ""});
    }

    return $self -> {"template"} -> load_template("tabs/container.tem", {"***options***"  => $options,
                                                                         "***contents***" => $hascontents ? " contents" : ""});
}


## @method $ build_pagination($maxpage, $pagenum, $mode, $count)
# Generate the navigation/pagination box for the message list. This will generate
# a series of boxes and controls to allow users to move between pages of message
# list.
#
# @param maxpage The last page number (first is page 1).
# @param pagenum The selected page (first is page 1)
# @param mode    The view mode
# @param count   The number of pages to show in the bar, defaults to 5. Odd numbers
#                are recommended whenever possible.
# @return A string containing the navigation block.
sub build_pagination {
    my $self    = shift;
    my $maxpage = shift;
    my $pagenum = shift;
    my $mode    = shift;
    my $count   = shift || 5;

    # If there is more than one page, generate a full set of page controls
    if($maxpage > 1) {
        my $pagelist = "";

        # If the user is not on the first page, we need to add the left jump controls
        $pagelist .= $self -> {"template"} -> load_template("paginate/firstprev.tem", {"***first***" => $self -> build_url(pathinfo => [$mode, 1]),
                                                                                       "***prev***"  => $self -> build_url(pathinfo => [$mode, $pagenum - 1])})
            if($pagenum > 1);

        # load some templates to speed up page list generation...
        my $pagetem    = $self -> {"template"} -> load_template("paginate/page.tem");
        my $pageacttem = $self -> {"template"} -> load_template("paginate/active.tem");
        my $spacertem  = $self -> {"template"} -> load_template("paginate/spacer.tem");

        # Work out where the start and end are
        my $start = $pagenum - int($count / 2);
        $start = 1 if($start < 1);

        my $end = $start + ($count - 1);
        $end = $maxpage if($end > $maxpage);

        # The first page is always visible in the list
        $pagelist .= $self -> {"template"} -> process_template($pagetem, {"***page***"    => $self -> build_url(pathinfo => [$mode, 1]),
                                                                          "***pagenum***" => 1})
            if($start > 1);

        # Potentially add a spacer if needed
        $pagelist .= $spacertem if($start > 2);

        # Generate the list of pages
        for(my $pnum = $start; $pnum <= $end; ++$pnum) {
            $pagelist .= $self -> {"template"} -> process_template(($pagenum == $pnum) ? $pageacttem : $pagetem,
                                                                   {"***page***"    => $self -> build_url(pathinfo => [$mode, $pnum]),
                                                                    "***pagenum***" => $pnum });
        }

        # Possibly add another spacer if not up against the right end
        $pagelist .= $spacertem if($end < ($maxpage - 1));
        $pagelist .= $self -> {"template"} -> process_template($pagetem, {"***page***"    => $self -> build_url(pathinfo => [$mode, $maxpage]),
                                                                          "***pagenum***" => $maxpage})
            if($end < $maxpage);


        # Append the right jump controls if we're not on the last page
        $pagelist .= $self -> {"template"} -> load_template("paginate/nextlast.tem", {"***last***" => $self -> build_url(pathinfo => [$mode, $maxpage]),
                                                                                      "***next***" => $self -> build_url(pathinfo => [$mode, $pagenum + 1])})
            if($pagenum < $maxpage);

        return $self -> {"template"} -> load_template("paginate/block.tem", {"***pagenum***" => $pagenum,
                                                                             "***maxpage***" => $maxpage,
                                                                             "***pages***"   => $pagelist});
    # If there's only one page, a simple "Page 1 of 1" will do the trick.
    } else { # if($maxpage > 1)
        return $self -> {"template"} -> load_template("paginate/block.tem", {"***pagenum***" => 1,
                                                                             "***maxpage***" => 1,
                                                                             "***pages***"   => ""});
    }
}


1;
