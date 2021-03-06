#!/usr/bin/perl -wT
# Note: above -w flag should be removed in production, as it will cause wrnings in non-AATL modules
# to appear in the server error log

use utf8;
use v5.12;
use lib qw(/var/www/webperl);

# Work out where the script is, so module and config loading can work.
our $scriptpath;
BEGIN {
    $scriptpath = "/home/chris/workstuff/aatl";
}

use CGI::Carp qw(fatalsToBrowser set_message); # Catch as many fatals as possible and send them to the user as well as stderr
use lib "$scriptpath/modules";

our $contact = 'contact@email.address'; # global contact address, for error messages

# System modules
use CGI::Carp qw(fatalsToBrowser set_message); # Catch as many fatals as possible and send them to the user as well as stderr

# Webperl modules
use Webperl::Application;

# Webapp modules
use AATL::AppUser;
use AATL::BlockSelector;
use AATL::System;

delete @ENV{qw(PATH IFS CDPATH ENV BASH_ENV)}; # Clean up ENV

# install more useful error handling
sub handle_errors {
    my $msg = shift;
    print "<h1>Software error</h1>\n";
    print '<p>Server time: ',scalar(localtime()),'<br/>Error was:</p><pre>',$msg,'</pre>';
    print '<p>Please report this error to ',$contact,' giving the text of this error and the time and date at which it occured</p>';
}
set_message(\&handle_errors);

my $app = Webperl::Application -> new(config         => "$scriptpath/config/site.cfg",
                                      appuser        => AATL::AppUser -> new(),
                                      system         => AATL::System -> new(),
                                      block_selector => AATL::BlockSelector -> new())
    or die "Unable to create application";
$app -> run();
