## @file
# This file contains the AATL-specific implementation of the runtime
# block selection class.
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

## @class
# Select the appropriate block to render a page based on an AATL URL.
# This allows a url of the form /courseid/feature/...otherpath../?args
# to be parsed into something the AATL classes can use to render pages
# properly, and select the appropriate block for the current request.
package BlockSelector::AATL;

use strict;
use base qw(BlockSelector);

# ============================================================================
#  Block Selection

## @method $ get_block($dbh, $cgi, $settings, $logger, $session)
# Determine which block to use to generate the requested page. This performs
# the same task as BlockSelector::get_block(), except that it will also parse
# the contents of the PATH_INFO environment variable into the query string
# data, allowing AATL paths to be passed to the rest of the code without
# the need to check both the query string and PATH_INFO.
# @param dbh      A reference to the database handle to issue queries through.
# @param cgi      A reference to the system CGI object.
# @param settings A reference to the global settings object.
# @param logger   A reference to the system logger object.
# @param session  A reference to the session object.
# @return The id or name of the block to use to render the page, or undef if
#         an error occurred while selecting the block.
sub get_block {
    my $self     = shift;
    my $dbh      = shift;
    my $cgi      = shift;
    my $settings = shift;
    my $logger   = shift;
    my $session  = shift;

    $self -> self_error("");

    my $pathinfo = $ENV{'PATH_INFO'};

    # If path info is present, it needs to be shoved into the cgi object
    if($pathinfo) {
         # strip off the script if it is present
        $pathinfo =~ s|^(/media)?/index.cgi||;

        # No need for leading /, it'll just confuse the split
        $pathinfo =~ s|^/||;

        # Split along slashes
        my @args = split(/\//, $pathinfo);

        my ($course, $block) = ("", "");

        # If there are two or more arguments, the course and block are set
        if(scalar(@args) >= 2) {
            $course = shift @args;
            $block  = shift @args;

        # A single argument means that a course has been specified but no block
        # so use the news block by default.
        } elsif(scalar(@args) == 1) {
            $course = shift @args;
            $block  = $settings -> {"config"} -> {"news_block"};

        # No course or block have been specified; the user is looking at the
        # front page of the course, so fall back on the site block.
        } else {
            $block  = $settings -> {"config"} -> {"site_block"};
        }

        $cgi -> param(-name => 'course', -value => $course);
        $cgi -> param(-name => 'block' , -value => $block);

        # Push any remaining components into the pathinfo variable
        $cgi -> param(-name => 'pathinfo', -values => \@args) if(scalar(@args));
    }

    # The behaviour of BlockSelector::get_block() is fine, so let it work out the block
    return $self -> SUPER::get_block($dbh, $cgi, $settings, $logger);
}

1;
