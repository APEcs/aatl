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
#  Question listing control.

## @method @
sub show_question_list {
    my $self = shift;



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

    # Is this an API call, or a normal news page call?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {

    } else {

        # User has access, generate the news page for the course.
        return $self -> generate_course_page($title, $content, $extrahead);
    }
}



1;
