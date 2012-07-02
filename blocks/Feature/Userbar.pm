## @file
# This file contains the implementation of the AATL user toolbar.
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

## @class Feature::Userbar
# The Userbar class encapsulates the code required to generate and
# manage the user toolbar.
#
# @note This is a Feature subclass, but it has no page_display - this is
#       intentional!
package Feature::Userbar;

use strict;
use base qw(Feature);

# ==============================================================================
#  Bar generation

## @method $ block_display()
# Generate a user toolbar, populating it as needed to reflect the user's options
# at the current time.
#
# @return A string containing the user toolbar html on success, undef on error.
sub block_display {
    my $self = shift;

    # Initialise fragments to sane "logged out" defaults.
    my ($coursemenu, $oldcourse, $coursetools, $userprofile, $hasfeedback) =
        ($self -> {"template"} -> load_template("userbar/coursemenu_none.tem"),
         $self -> {"template"} -> load_template("userbar/state_current.tem"),
         $self -> {"template"} -> load_template("userbar/coursetools_invisible.tem"),
         $self -> {"template"} -> load_template("userbar/profile_loggedout.tem"),
         $self -> {"template"} -> load_template("userbar/feedback_none.tem"));

    # Is the user logged in?
    if(!$self -> {"session"} -> anonymous_session()) {
        my $user = $self -> {"session"} -> get_user_byid()
            or return undef;

        # User is logged in, so actually reflect their current options and state
        $userprofile = $self -> {"template"} -> load_template("userbar/profile_loggedin.tem", {"***realname***"    => $user -> {"fullname"},
                                                                                               "***username***"    => $user -> {"username"},
                                                                                               "***gravhash***"    => $user -> {"gravatar_hash"},
                                                                                               "***url-profile***" => $self -> build_url(block => "profile"),
                                                                                               "***url-prefs***"   => $self -> build_url(block => "settings"),
                                                                                               "***url-logout***"  => $self -> build_url(block => "login", paramstr => "logout=t")});

        # Determine whether the user has new feedback
#        FIXME: Make this actually work
#        $hasfeedback = $self -> {"template"} -> load_template("userbar/feedback_new.tem")
#            if($self -> {"system"} -> {"feedback"} -> user_has_feedback($self -> {"session"} -> get_user_byid()));

        my $courseid = $self -> determine_courseid();

        # Is the user looking at an old course?
#        FIXME: Make this actually work
#        $oldcourse = $self -> {"template"} -> load_template("userbar/state_old.tem")
#            if($self -> {"system"} -> {"courses"} -> course_is_closed($courseid));

        # Does the user have access to the tools?
#        FIXME: Make this actually work
#        $coursetools = $self -> build_course_tools($courseid, $user);

        # And which courses can the user view?
#        FIXME: Make this actually work
#        $coursemenu = $self -> build_course_menu($courseid, $user);
    } # if(!$self -> {"session"} -> anonymous_session())

    return $self -> {"template"} -> load_template("userbar/userbar.tem", {"***coursemenu***"    => $coursemenu,
                                                                          "***coursestate***"   => $oldcourse,
                                                                          "***coursetools***"   => $coursetools,
                                                                          "***userprofile***"   => $userprofile,
                                                                          "***feedbackstate***" => $hasfeedback});
}

1;
