## @file
# This file contains the implementation of the AATL Protocol class.
#
# @author   Jacobus Meulen 8lt;jack@jacobusmeulen.co.uk&gt;
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
# along with this program.  If not, see http://www.gnu.org/licenses/.

## @class Protocol
package Protocol;
use File::Basename;

# We define our message types here
our $CONVERT_VIDEO="CONV_VIDEO";
our $seperator    ="[--]";

##
## Below follow some methods that are used to comply to the
## standard formatting of the protocol. These should be used
## to generate the packages that are sent to the server, and 
## can be used by the server to effectively decode the information
##

#sub generate_packet
#{
#  my $header = $CONVERT_VIDEO;
#  my $video_url = shift;
#  my $video_tgt = shift;
  
#  # Anything Else here
  
#  my $packet = "$video_url::$video_tgt";
#}

sub untaint_file
{
  my $protocol = shift;
  my $filename = shift;
  
  my ($name, $path, $ext) = fileparse( $filename, '\..*');
  $filename = $name . $ext;
  
  if( $filename =~ /^([-\@\w.]+)$/ )
  {  
   # return $path . $1 if( $path ne "./" );
    return $1;
  }
  
  return undef;
}

## @method $ map_to_string(HASH_MAP)
# Every data packet that needs to be sent to the server must be 
# encoded into a single string using this method. It converts
# a hash map into a string which can be sent over the socket connection.
# @return An encoded string that contains all the values in the given hash.
sub map_to_string
{
  my %map = @_;
  my $string = "";
  
  # Loop through all the values in the hash
  while(my($key, $value) = each %map)
  {
    # Correct any problems with illegal characters
    $key = parse_string($key);
    $value = parse_string($value);
    
    # Encode the map into a string
    $string = $string . "<___>" unless ($string eq "");
    $string = $string . "$key=$value";
  }
  
  return $string;
}

## @method $ string_to_map(ENCODED_STRING)
# The inverse of map_to_string. This method decodes the encoded
# string produced by map_to_string, and splits it back up into
# a hash map
# @return A Hash Map containing all the variables present in the string
sub string_to_map
{
  # Given the consistent seperator, we can split the string up
  # back into key-value pairs
  my @args = split("<___>", shift);
  my %map;
  
  # We can now loop through our key-value pairs, and split them
  # up into keys and values, assigning them to the appropriate hash
  foreach(@args)
  {
    my @pair = split("=");
    $map{@pair[0]} = @pair[1];
  }
  
  # Now we only have to return a reference to the hash
  return \%map;
}

## @method $ parse_string(STRING)
# A helper method which removes any illegal symbols from a given string
# and returns it.
# @return The input string with any illegal symbols removed.
sub parse_string
{
  my $string = shift;
  
  # We remove the symbols we use to encapsulate our message. 
  # The rest we don't really care about.
  $string =~ s/=//g;
  $string =~ s/\t//g;
  
  return $string;
}

# our 
