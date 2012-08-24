## @file
# This file contains the implementation of the AATL video functionality
#
# @author  Jacobus Meulen &lt;jack@jacobusmeulen.co.uk&gt;
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

## @class System::Materials::Video
# This class encapsulates the operations required by the video functionality
# in the website
package System::Materials::Video;

use strict;
use base qw(SystemModule);

use File::Basename;
use File::Temp qw/ tempfile tempdir /;

use Data::Dumper;
use IO::Socket;

# ==============================================================================
#  Create

## @cmethod $ new(%args)
# Create a new V8deo object to manage videos and in-video quizes.
# The minimum values you need to provide are:
#
# * dbh          - The database handle to use for queries.
# * settings     - The system settings object
# * logger       - The system logger object.
# * roles        - The system roles object.
# * courses      - The system courses object.
# * metadata     - The system metadata object.
#
# @param args A hash of key value pairs to initialise the object with.
# @return A new Video object, or undef if a problem occurred.
sub new
{
    my $invocant = shift;
    my $class 	 = ref($invocant) || $invocant;
    my $self 	 = $class -> SUPER::new(@_);
    
    return undef if(!$self);
    
    return $self;
}

# ===============================================================================
#   Uploading

## @method $ upload_video($courseid, $userid, $cgi, $form_videoid, $target_filename)
# Upload a video to the server, as the specified filename. 
#
# @param courseid 	 The ID of the course this video is being uploaded for.
# @param userid   	 The ID of the user who is uploading this video
# @param cgi 	 	 A CGI instance object containing the form data for the video.
# @param form_videoid 	 The identifier specifying the video POST data.
# @param target_filename The target filename for the specified video without extension.
sub upload_video
{
    my $class		= shift;
    my $self 	     	= shift;
#    my $courseid	= shift;
#    my $userid		= shift;
    my $cgi 	     	= shift;
    my $form_videoid   	= shift;
    my $target_filename = shift;
    
    # Clear any previous errors
    $self -> clear_error();
    
    # Get the coure metadata context ID
 #   my $parentid = $self -> {"courses"} -> get_course_metadataid($courseid)
 #   		   or return $self -> self_error("Unable to obtain course metadata id: ". $self -> {"courses"} -> {"errstr"} 
	#	   				 || "Course does not exist");
    
#    my $metadataid = $self -> {"metadata"} -> create($parentid)
    	#	   or return $self -> self_error("Unable to create new metadata context: ". $self -> {"metadata"} -> {"errstr"});
  
    		   
    
    # Now we're ready to process the video
    my $safe_chars = "a-Z0-9_.-";
    my $upload_dir = $self -> {"settings"} -> {"setup"} -> {"Core::temp"};

    my $src_video_file =  $cgi -> param($form_videoid);

    # Check if a video file was actually specified
    return $self -> self_error("Unable to upload video: No video specified")
    	     unless( $src_video_file );

    # Remove the pathname from the file
    my ($src_video_name, $src_path, $src_ext) = fileparse( $src_video_file, '\..*');
    $src_video_file = $src_video_name . $src_ext;
    
    # Make filename safe
    return $self -> self_error("Unable to upload video: Illegal filename specified")
             unless( defined ($src_video_file = _untaint_file( $src_video_file )) );

    # Now upload the file
    # say "<p>Acquiring upload handler for $video_file</p>";
    my $upload_handle = $cgi -> upload($form_videoid);

    return $self -> self_error("Unable to upload video: Could not establish an upload handler") 
            unless (defined ($upload_handle));

    my $output_file = "$target_filename$src_ext";
    $output_file = _untaint_file($output_file);
    
    # And Save the file on the server
    open VIDEOFILE, ">" . $upload_dir . "/" . $output_file
    	or return $self -> self_error("Unable to open $output_file for writing: ". $!);
 
    # Would be required to track progress
    my $total_size = -s $upload_handle;
    
    # Remember to save it as a binary file
    binmode VIDEOFILE;

    #say "<p>Writing into file $upload_dir/$video_file</p>";
    #say VIDEOFILE;
    #say "Handle: " . $upload_handle;
    # And write it into the file
    while( <$upload_handle> )
    {
      print VIDEOFILE $_;
    }

    # Finally, close the stream
    close VIDEOFILE;

    # And return the full pathname
    return "$upload_dir/$output_file";
} 

## @method $ map_to_string(HASH_MAP)
# Every data packet that needs to be sent to the server must be 
# encoded into a single string using this method. It converts
# a hash map into a string which can be sent over the socket connection.
# @return An encoded string that contains all the values in the given hash.
sub map_to_string
{
  my $class = shift;
  my %map = @_;
  my $string = "";
  
  # Loop through all the values in the hash
  while(my($key, $value) = each %map)
  {
    # Correct any problems with illegal characters
#    $key = parse_string($key);
#    $value = parse_string($value);
    
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
  my $class = shift;
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

## @method $ dispatch_video(SELF, ENCODED_STRING)
#  Dispatches the video to the server for conversion. 
sub dispatch_video
{
   my $class = shift;
   my $self  = shift;
   my $args  = shift;
   
   my $connection = new IO::Socket::INET (
   				PeerAddr => '127.0.0.1',
				PeerPort => '7070',
				Proto    => 'tcp' )
	or return $self -> self_error("Unable to establish TCP connection: $!");

   print $connection "CONV_VIDEO\t$args";
   
   close $connection;
}

## @method $ video_status
#  Sends a request to the server to get information about the status
#  of the video. This will return CONVERTING or QUEUED [POSITION] if there weren't
#  any errors, giving more information to the user about how long the process will take.
#  ERROR [ERROR_STRING] is returned if there was a problem with the video conversion
#  process. This can be logged, and the user should be notified.
sub video_status
{
}

# ================================================================================
#   Internals

## @method $ upload_video($courseid, $userid, $cgi, $form_videoid, $target_filename)
sub _upload_video
{
}

sub _untaint_file
{
  my $filename = shift;
  
  my ($name, $path, $ext) = fileparse( $filename, '\..*');
  $filename = $name . $ext;
  
  print STDERR "Untaining: " . $filename;
  
  if( $filename =~ /^([-\@\w.]+)$/ )
  {  
    return $1;
  }
  
  return undef;
}

1;
