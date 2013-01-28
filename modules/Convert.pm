## @file
# This file contains the implementation of the AATL video-conversion class.
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

## @class Convert
# 
package Convert;

# There are a few non-standard dependencies for this functionality.
use strict;
use MP4::Info;
use Video::Info; # This library is best installed as the package libvideo-info-perl. It relies on an old library called openquicktime, which is a hell to install by itself

use Data::Dumper;

# Standard Dependencies
use POSIX; # In particular, we need the floor() method

# We define a global variable for $debug_flag. Since this value is only checked and never changed, it is safe and sensible.
our $debug_flag = 0;


# Testing Code
# &validate_video("../video/Output_2.flv");
# validate_video("../video/hello2.ogv");
# validate_video("../video/Agnis_Philosophy_Final_Fa-RAAGMP3.CoM.flv");
# validate_video("../video/big_buck_bunny_480p_stereo.ogg");
# convert_video("../video/Agnis_Philosophy_Final_Fa-RAAGMP3.CoM.mp4", "flv");

# my $convert = new Convert();
# $convert -> convert_video("../video/Agnis_Philosophy_Final_Fa-RAAGMP3.CoM.mp4", "flv", "mtempt");

## @method $ new()
#
#
sub new
{
  my $invocant = shift;
  my $class    = ref($invocant) || $invocant;
  
  my $width  = 640;
  my $height = (640 / 16) * 9; # ( Width / (Aspect Left) ) * (Aspect Right) 
  
  my $self  = {
       ffmpeg => '/usr/bin/ffmpeg',
       ffprobe=> '/usr/bin/ffprobe',
       q_flag => 0,		# Default, User Specified, Not Recommended
       width  => $width,	# Default, User Specified
       height => $height,	# Default, User Specified
       max_file_size_mb  => 20, # Default, User Specified
       max_bitrate	 => 790, # Should probably let this depend on the source file
       @_
  };
    
  bless $self, $class;
  return $self;
}

## @method $ convert_video(VIDEO_URL,OUTPUT_FORMAT_EXT,TEMP_FILE)
# Converts a video from its base format in the VIDEO_URL to the output format
# specified by OUTPUT_FORMAT_EXT. It starts by doing a sanity check - is the file
# actually a video. If it isn't, the method returns undef. Otherwise, it returns
# the URL of the resulting video file. 
# @return undef on failure, or a string containing the new URL on success.
sub convert_video
{
  my $self = shift;

  my $source_video    = shift;
  my $destination_ext = shift; 
  my $temp_file	      = shift;
  
  # The list of supported formats as of 20/06/2012
  my $supported_formats = "(\.mp4|\.ogv|\.ogg|\.flv|\.mpg|\.avi|\.asf|\.wmv)";
 
  my $video	      = $source_video;
  my $source_ext      = "";
  my $destination_video = ""; 
  
  
  # First we remove the dot from the destination extension (e.g. '.mp4' becomes 'mp4')
  $destination_ext    =~ s/\.//i;
  
  # Now remove the extension from the video file, using the templates of supported formats
  # This may not work on all files as it is now. Should be restricted to the final letters
  # of the $video string. 
  $video	      =~ s/$supported_formats//i;
  
  # print "Not supported\n";
  # Return if file doesn't show up in supported formats (It should! FIX YOUR WEBFORM!)
  return undef if ( $video eq $source_video);
  
  # Now we get the extension of the original file by taking the string difference
  $source_ext	      = $video ^ $source_video;
  
  # And finally, we append the destination extension to our destinion url
  $destination_video  = $video . ".$destination_ext";
  
  # Temporary helper code
  # print "Source File: " . $source_video . "\n";
  # print "Destination File: " . $destination_video . "\n";
  
  # Validate that the 'video file' is actually a video file.
  my $video_info = validate_video($source_video); 
  return undef if( not defined $video_info );
  
  # Given a video length in seconds, and a maximum allowed file size,
  # we can approximate an optimal bitrate for the video. The file
  # size should be chosen dependent on the video dimensions, which 
  # currently default to 640x360. Remember, we're calculating bits, not
  # bytes, so the file size must be multiplied by 8 to convert from bytes to bits.
  my $video_length_seconds = $video_info -> {"length_in_seconds"};
  my $bitrate = ($self -> {'max_file_size_mb'} * 1024 * 8) / $video_length_seconds;  
  
  print "Setting bitrate to ".floor($bitrate)."k\n";
  
  # Floor the bitrate so we get a full number
  $bitrate = floor($bitrate);
  
  # Truncate the bitrate and append k to the string.
  $bitrate = $bitrate > $self -> {'max_bitrate'} ? $self -> {'max_bitrate'} . "k" : "$bitrate"."k";
  
  # Now we're ready to convert
  if( $self -> {"q_flag"} )
  {
    system($self -> {"ffmpeg"}, "-i", "$source_video", "-sameq", "$video.$destination_ext");
  }
  else
  {
    if($temp_file ne "")
    {
      print "Logging in $temp_file\n";
      
      my $codec = get_codec($destination_ext);
      print "Calling: ffmpeg -i $source_video -b $bitrate -vstats_file $temp_file -vcodec $codec  $video.$destination_ext\n";
      my $error = system($self -> {"ffmpeg"}, "-i", "$source_video", "-y", "-b", "$bitrate", "-vstats_file", $temp_file, "-vcodec", $codec, "-vpre", "normal", "$video.$destination_ext"); 
      print "Error: $!\n" if $error ne 0;
    }
    else
    {
      print "Calling: ffmpeg -i $source_video -b $bitrate $video.$destination_ext\n";
      system($self -> {"ffmpeg"}, "-i", "$source_video", "-y", "-b", "$bitrate", "$video.$destination_ext");
    }
  }
}

sub get_codec
{
  my $video_format = shift;
  
  if($video_format eq "mp4" or $video_format eq ".mp4")
  {
    return "libx264";
  }
  
  return "libx264";
}

## @method $ validate_video(VIDEO_URL)
# This method validates a given video string. The convert_video method calls this
# method to verify that the given file is actually a video file. It returns 1 if
# it is a valid video file, otherwise 0.
# @return 1 if the file is a video file, 0 otherwise
sub validate_video
{
  my $claimed_video   = shift;
  
  # Make sure we actually have some data in the video file. 
  if( not defined $claimed_video )
  {
    debug_println("No video has been specified at: Convert.pl: validate_video()");
    return undef;
  }
  
  # Check, for each format, if the video belongs to it. If it does, return 1, otherwise 0.
  if( is_mp4($claimed_video)  )
  {
    debug_println("$claimed_video is a Mp4 file");
    return get_mp4_info($claimed_video);
  }
  elsif( is_flv($claimed_video) )
  {
    debug_println("$claimed_video is a FLV file");
    return get_flv_info($claimed_video); 
  }
  elsif( is_ogg($claimed_video) )
  { 
    debug_println("$claimed_video is an OGG Theora file");
    return get_ogg_info($claimed_video);
  }
  elsif( is_other_video($claimed_video) )
  {
    debug_println("$claimed_video is of a supported, but unspecified file format");
    return get_other_video_info($claimed_video);
  }
  else
  {
    debug_println("$claimed_video is in an unsupported format");
    return undef;
  }
}

## @method $ get_ffprobe_info(VIDEO_URL, VIDEO_INFO)
# After acquiring information about the video file, and thus validating that the file is an actual
# video file, we may run ffprobe to acquire additional information about the video file.
# @return VIDEO_INFO, corrected with the appropriate variables
sub get_ffprobe_info
{
  my $url  = shift;
  my $info = shift;
  
  
 # print for qx{ffprobe ../../public_html/video/hello.ogg};
#     length_in_seconds => undef,
#     bitrate	       => undef,
#     height	       => undef,
#     width	       => undef,
#     fps	       => undef
}

## @method $ is_flv_old(VIDEO_URL)
# Checks if the video given in the string VIDEO_URL is a video contained in an FLV container. 
# Deprecated now. It's too slow for the task it needs to perform. Replaced with is_flv(VIDEO_URL)
# @return True if it is an FLV file, False otherwise.
sub is_flv_old
{
  my $video = shift;
 # my $reader = FLV::Info -> new();
  
  # FLV Info throws an exception if the FLV file is unable to be parsed.
  # Catching this exception allows us to determine if a file is FLV or not.
 # eval{ $reader -> parse( $video ) };
 # my $result = !($@ ne '');
  
  # Now we need to unset $@, as it would otherwise incorrectly be remembered
  $@ = "";
  
  return 0;
  #return $result;
}

## @method $ is_mp4(VIDEO_URL)
# Checks if the video given in the string VIDEO_URL is a video contained in an MP4 container. 
# @return True if it is an Mp4 file, False otherwise.
sub is_mp4
{
  my $video = shift;
  my $info;
  
  # MP4 Info sets $@ to an exception when the file is not possible to parse.
  # Any file that can't be parsed by Mp4 Info is not an Mp4 file.
  $info = get_mp4info( $video ); 
  my $result = !($@ ne '');
  
  # Now we need to unset $@, as it would otherwise incorrectly be remembered
  $@ = "";
  
  return $result;
}

## @method $ get_mp4_info(VIDEO_URL)
# This method assumes the given file is an mp4 file, and should therefore be preceded by a check
# with the method is_mp4(VIDEO_URL).
# This method retrieves some general information about the video file, such as video length,
# bitrate and resolution, and returns it in a video_info package.
# @return A video_info package containing length_in_seconds, bitrate and height
sub get_mp4_info
{
  my $video = shift;
  my $info;
  my %video_info = {
     length_in_seconds => undef,
     bitrate	       => undef,
     height	       => undef,
     width	       => undef,
     fps	       => undef
  };
  
  $info = get_mp4info( $video );
  
  
  $video_info{"length_in_seconds"} = $info -> {"SECS"};
  $video_info{"bitrate"} = $info -> {"BITRATE"};
  
  return \%video_info
}

## @method $ is_ogg(VIDEO_URL)
# This method checks if the specified file is contained as an OGG file, and is
# encoded as a Theora file, which is the video file of the OGG type. The audio
# files are encoded using Vorbis, and are considered invalid input files by
# this method. 
# @return 1 if the file is Ogg Theora, 0 otherwise.
sub is_ogg
{
  my $video = shift;
  my $buffer = "";
  my $correct = 1;
  
  open_binfile($video);
  
  # First we read the magic numbers
  read( INF, $buffer, 1 );
  $correct = ($buffer eq 'O') && $correct;
  read( INF, $buffer, 1 );
  $correct = ($buffer eq 'g') && $correct;
  read( INF, $buffer, 1 );
  $correct = ($buffer eq 'g') && $correct;
  read( INF, $buffer, 1 );
  $correct = ($buffer eq 'S') && $correct;
  
  if (not $correct)
  {
    close_binfile();
    return 0;
  }
  
  read( INF, $buffer, 1 ); # Stream Structure Version
  $correct = (ord($buffer) == 0x00) && $correct;
  
  read( INF, $buffer, 1 ); # Header type flag, should be 0x01, 0x02 or 0x04
  $correct = (ord($buffer) == 0x02) && $correct; # Any sane Ogg file will start with a header of type 0x02
  
  read( INF, $buffer, 20 ); # We don't need the next 20 bytes, specifying serial numbers and positions
  read( INF, $buffer, 1  ); # Number of Page Segments
  
  $buffer = hex ord($buffer);
  read( INF, $buffer, $buffer ); #Skip the segment table
  
  read( INF, $buffer, 1 );
  $correct = (ord($buffer) == 0x80) && $correct;
  warn "An Ogg Vorbis file was specified. A Ogg Theora file was expected" if(ord($buffer) == 0x01); 
  
  read( INF, $buffer, 1 );
  $correct = ($buffer eq 't') && $correct;
  read( INF, $buffer, 1 );
  $correct = ($buffer eq 'h') && $correct;
  read( INF, $buffer, 1 );
  $correct = ($buffer eq 'e') && $correct;
  read( INF, $buffer, 1 );
  $correct = ($buffer eq 'o') && $correct;
  read( INF, $buffer, 1 );
  $correct = ($buffer eq 'r') && $correct;
  read( INF, $buffer, 1 );
  $correct = ($buffer eq 'a') && $correct;
  
  close_binfile();
  return $correct;
}

## @method $ get_other_video_info(VIDEO_URL)
# This method gets the video information of MPEG, RIFF, ASF and QuickTime formats.
# It assumes that the video_url specifies a valid video, and must therefore be
# preceded by the is_other_video(VIDEO_URL) check. 
# @return A video_info object containing length_in_seconds and bitrate
sub get_ogg_info
{
  my $video = shift;
  my $info;
  my $width; my $height;
  my $byte1; my $byte2; my $byte3; # For 24 bit numbers
  my $frn; my $frd; my $fps;
  my $bitrate;
  my $duration;
  
  my %video_info = {
     length_in_seconds => undef,
     bitrate	       => undef,
     height	       => undef,
     width	       => undef,
     fps	       => undef
  };
  
  open_binfile($video);
  
  my $buffer;
  
  # Skip to the metadata
  seek INF, 26, 0; # Skip the first 26 OggS bits
  read INF, $buffer, 1; # Read the number of page segments
  seek INF, hex(ord($buffer)), 1; # Skip the segments table
  seek INF, 7, 1; # Skip the theora magic number
  
  # We read the versions to validate we're looking at the right
  # data. If we're not, we return undef.
  read INF, $buffer, 1;
  return undef if ( hex(ord($buffer)) != 3 );
  read INF, $buffer, 1;
  return undef if ( hex(ord($buffer)) != 2 );
  read INF, $buffer, 1;
  return undef if ( hex(ord($buffer)) != 1 );
  
  # We can skip the FMBW and FMBH tags
  seek INF, 4, 1;
    
  # Now we read the width
  read INF, $buffer, 3;
  ($byte1, $byte2, $byte3) = unpack('C3', $buffer);
  $width = (65536 * $byte1) + (256 *$byte2) + $byte3;
  
  # And the height
  read INF, $buffer, 3;
  ($byte1, $byte2, $byte3) = unpack('C3', $buffer);
  $height = (65536 * $byte1) + (256 *$byte2) + $byte3;
  
  seek INF, 2, 1; # Skip the next two bytes
  
  # Get the frame rate nominator and denominator
  read INF, $buffer, 4;
  my @val = unpack("N", $buffer);
  $frn = @val[0];
  
  read INF, $buffer, 4;
  @val = unpack("N", $buffer);
  $frd = @val[0];
  
  # Calculate the frames per second
  $fps = $frn;
  $fps = ($frn / $frd) unless ($frd == 0);
  
  # We don't need any of the data in the next 7 bytes
  seek INF, 7, 1;
  
  # Now we get the nominal bitrate hint, and check if it looks reasonable
  read INF, $buffer, 3;
  ($byte1, $byte2, $byte3) = unpack('C3', $buffer);
  $bitrate = (65536 * $byte1) + (256 *$byte2) + $byte3;
  
  # We need to get KFGSHIFT, which is defined by bits 7-12 in this 16 bit number
  read INF, $buffer, 2;
  ($byte1, $byte2) = unpack('C2', $buffer);
  my $tt = unpack('b32', $buffer);
  debug_println("KFGShift: $tt");
  my $kfgshift = (256 * $byte1) + $byte2;
  
  # We get the 5 bits we're looking for by a logical AND with the number
  # 0000 0011 1110 0000 = 992
  $kfgshift = $kfgshift & 992;
  
  # The next step is to shift the values to the appropriate position,
  # otherwise the number will be incorrect
  $kfgshift = $kfgshift >> 5; # We shift by 5, as that's the number of trailing zeros 
  debug_println(18000/60);
  
  # Let's remember our current position
  my $cur_pos = tell();
  
  # We get the last page
  #seek INF, 
  
  # We try to find the last packet as quickly as possible.
  # To do this, we look at the last 100 000 bytes of the file,
  # and see if any OggS packet starts there. If it doesn't, we
  # return to our original position and check again.
  # If no packet was found, $granule_position will be undef,
  # and this method returns undef, as the file appears to be
  # malformed.
  my $granule_position = undef;
  my $debug_counter = 0; my $eof_reached = 0;
  my $last_page_reached = 0;
  
  seek INF, 0, 2;
  seek INF, -100000, 2 if( tell() - $cur_pos > 100000 );
  while( not $last_page_reached || (eof(INF) && $eof_reached))
  {
    read( INF, $buffer, 1 );
    if($buffer eq 'O')
    {
      # We read the rest of the magic number, and bomb out if it doesn't match
      read( INF, $buffer, 1 );
      next if($buffer ne 'g');
      read( INF, $buffer, 1 );
      next if($buffer ne 'g');
      read( INF, $buffer, 1 );
      next if($buffer ne 'S');
      
      # Now we're definitely in an OggS header
      seek INF, 1, 1; # We don't care about the version
      read INF, $buffer, 1;
      
      # If we reach a page with the value 0x04, we've reached the last page
      $last_page_reached = (ord($buffer) == 0x04);
      
      # The next 8 bytes represent the granule position
      read INF, $buffer, 8;
      
      # We put it into a bit string, and we split that into LHS and RHS based on KFG Shift
      # LHS is 0-KFGShift, and RHS is the rest.
      my $string = unpack('b64', $buffer);
      my $lhs_str = substr $string, 0, $kfgshift;
      my $rhs_str = substr $string, $kfgshift;
      
      # Now we can convert the previously acquired strings into decimals.
      # We need to reverse the order to get the correct values.
      my $lhs = oct("0b".reverse $lhs_str);
      my $rhs = oct("0b".reverse $rhs_str);
      
      # The final page contains a bit string made up entirely out of ones
      # for the granule position. This is defined by the standard, and we should therefore
      # choose to pick the next-to-last packet, and use that granule_position.
      $granule_position = $rhs + $lhs unless $last_page_reached;
      
      debug_println($granule_position);
      
      # Now we can skip some bytes to speed up the method
      seek INF, 12, 1; # Skip the next 12 bytes
      read INF, $buffer, 1;
      seek INF, hex(ord($buffer)), 1; # Skip the segment table
     # debug_println("Current Packet: $debug_counter");
     # $debug_counter++;
      
    }
    
    elsif($buffer eq 't')
    {
      read( INF, $buffer, 1 );
      next if($buffer ne 'h');
      read( INF, $buffer, 1 );
      next if($buffer ne 'e');
      # Can skip some more here
    }
    
    if(eof(INF) && not $eof_reached)
    {
      seek INF, $cur_pos, 0; # Fall Back to the original position if our initial guess didn't work out.
      $eof_reached = 1; # Make sure we don't reach this statement again, in case of malformed files
    }
  } 
  
  # If we haven't acquired a granule position, we're dealing with a malformed or incomplete file. 
  # We close the binary stream and return undef.
  if( not defined $granule_position )
  { 
    close_binfile();
    return undef;
  }
  
  # If the bitrate is 0, the encoder hasn't bothered to estimate it.
  # Instead, we approximate it.
  if( $bitrate == 0 )
  {
    $duration = 234;
   
    seek INF, 0, 2;
    $bitrate = calculate_video_bitrate( tell(), $duration, 192);
    
    debug_println("Bitrate was zero - approximating...");
    
  }
  
  $duration = $granule_position / $fps;
  
  close_binfile();
  
  $video_info{"length_in_seconds"} = $duration; 
  $video_info{"bitrate"} = $bitrate;
  $video_info{"height"}	 = $height;
  $video_info{"width"}	 = $width;
  $video_info{"fps"}	 = $fps;
 
  debug_println("Granule Position: $granule_position");   
  debug_println("Length: " . $duration);
  debug_println("Bitrate: " . $bitrate);
  debug_println("Height: " . $height);
  debug_println("Width: " . $width);
  debug_println("FPS: " . $fps);
  
  
  return \%video_info;
  # Now we can convert our 35 bytes to a binary string
  #my @bit_string = pack("b", $buffer);
  #print @bit_string . "\n";
}

## @method $ is_other_video(VIDEO_URL)
# This method checks if the given video file is of type MPEG, RIFF (AVI,DivX), 
# ASF or Quicktime formats.
# @return 1 if the file is a supported video file, 0 otherwise.
sub is_other_video
{
  my $video = shift;
  
  $@ = sub { my $info = Video::Info -> new(-file=>$video) };
  
  my $result = !($@ ne '');
  
  # Now we need to unset $@, as it would otherwise incorrectly be remembered
  $@ = "";
  
  return $result;
}

## @method $ get_other_video_info(VIDEO_URL)
# This method gets the video information of MPEG, RIFF, ASF and QuickTime formats.
# It assumes that the video_url specifies a valid video, and must therefore be
# preceded by the is_other_video(VIDEO_URL) check. 
# @return A video_info object containing length_in_seconds and bitrate
sub get_other_video_info
{
  my $video = shift;
  my $info;
  my %video_info = {
     length_in_seconds => undef,
     bitrate	       => undef,
     height	       => undef,
     width	       => undef,
     fps	       => undef
  };
  
  $info = Video::Info -> new(-file=>$video);
  $video_info{"length_in_seconds"} = $info -> duration();
  $video_info{"bitrate"} = $info -> vrate();
  $video_info{"height"}  = $info -> height();
  
  return \%video_info;
}

## @method $ is_flv(VIDEO_URL)
# A pure perl implementation of a header check. This method checks if the given
# file header matches that of an FLV video file. It uses the magic number, specified
# by 4 UINT8 digits, the version, and the flags block to determine if the header is valid.
# It only returns true if all the checks indicate a valid FLV file.
# @return Returns 1 if the video is an FLV video, and 0 otherwise.
sub is_flv
{
  # A set of variables will be required to store the header
  my $claimed_flv     = shift;
  my $sig_F	      = "";
  my $sig_L	      = "";
  my $sig_V	      = "";
  my $version	      = "";
  
  my $flags_block     = "";
  
  my $data_offset     = "";
  
  # print "Converting: $claimed_flv\n";
  
  return 0 if( not defined $claimed_flv );
  
  # Open the given file for reading
  open_binfile( $claimed_flv );
  
  # The FLV container has a header that starts with 4 UI8 values.
  read( INF, $sig_F, 1 ); 
  read( INF, $sig_L, 1 ); 
  read( INF, $sig_V, 1 ); 
  read( INF, $version, 1 ); 
 
  read( INF, $flags_block, 1 );
  read( INF, $data_offset, 4 );
  
  $flags_block = hex(ord($flags_block)) . "\n";
  # $flags_block = sprintf("%08b\n", $flags_block); # Convert to binary representation
  # print $flags_block;
  
  # Debug Block
  #print "Signature: $sig_F$sig_L$sig_V \0\n";
  #print "Version: " . (hex ord($version)) . "\n";
  #print "Audio Flags: Found" . "\n" if($flags_block == 4 || $flags_block == 5); 
  #print "Video Flags: Found" . "\n" if($flags_block == 1 || $flags_block == 5);
  #print "\n";
  
  # Close the file
  close_binfile();
  
  # We will only support files that are FLV and contain a video stream
  # Note that the FLV container specifies if the file contains a video
  # stream in the flags block. This is the least significant binary 
  # digit. Everything else in the file, besides the audio stream flag,
  # is defined as 0 according to the specification. This gives two possibilities:
  # 0x00000101 if the file has both a video and an audio stream
  # 0x00000001 if the file only contains a video
  return ( $sig_F == 'F' && $sig_L == 'L' && $sig_V == 'V' && ($flags_block == 1 || $flags_block == 5));
}

## @method $ get_other_video_info(VIDEO_URL)
# This method gets the video information of MPEG, RIFF, ASF and QuickTime formats.
# It assumes that the video_url specifies a valid video, and must therefore be
# preceded by the is_other_video(VIDEO_URL) check. 
# @return A video_info object containing length_in_seconds and bitrate
sub get_flv_info
{
  my $video = shift;
  my $info;
  my %video_info = {
     length_in_seconds => undef,
     bitrate	       => undef,
     height	       => undef,
     width	       => undef,
     fps	       => undef
  };
  
  open_binfile($video);
  
  seek INF, 0, 2;
  my $filesize = tell();
  my $pack_size = undef;
  my $timestamp = undef;
  my $timestamp_2 = undef;
  my @pack_bfr  = undef;
  
  # First we set our file handler to the final bytes of the file
  seek INF, -4, 2;  
  
  # These 4 bytes/32 bits are a 32bit integer value, so we unpack and store them
  read INF, $pack_size, 4;
  @pack_bfr = unpack( "N", $pack_size );
  $pack_size = $pack_bfr[0];
  
  # Now we skip to the start of the last packet
  seek INF, -($pack_size+4), 2;
  seek INF, 4, 1;
  
  # Reset pack_bfr
  @pack_bfr = undef;
  
  # We have now arrived at the time stamp, which we can read and convert
  read INF, $timestamp, 3;
  read INF, $timestamp_2, 1;
  @pack_bfr = unpack( "N", $timestamp_2 . $timestamp );
  $timestamp = $pack_bfr[0];
  
  # We then convert the timestamp to seconds
  $timestamp /= 1000;
  
  $video_info{"length_in_seconds"} = floor($timestamp);
  
  # We have to approximate the bitrate
  $video_info{"bitrate"} = calculate_video_bitrate($filesize, $timestamp, 192);
  debug_println($timestamp);
  close_binfile();
  
  return \%video_info;
}

## @method $ calculate_video_bitrate(FILE_SIZE,VIDEO_LENGTH,AUDIO_BITRATE)
#
#
sub calculate_video_bitrate
{
  # We can approximate the video bitrate by assuming two things
  # 1. Audio Bitrate is fixed at 192 Kbits/ second
  # 2. File Size is calculated by (Audio BR + Video BR) * time_in_seconds.
  # Re-arranging the terms gives us the following solution.
  my $filesize = shift;
  my $timestamp = shift;
  my $audio_bitrate = shift;
  return ((( ($filesize / 1024) * 8) / $timestamp) - $audio_bitrate);
}

## @method $ open_binfile
# A simple helper method that opens a binary input stream
sub open_binfile
{
  my $file 	      = shift;
  
  return 0 if( not defined $file );
  
  open INF, $file  or die "\nCan't open $file for reading!\n";
  binmode INF;
}

## @method $ close_binfile
# A simple helper method that closes a binary input stream
sub close_binfile
{
  close INF or die "\nCan't close %file!\n";
}

## @method $ debug_println(TEXT)
# This method is intended to be used for printing off debugging information.
# It will only result in any information being printed off if the debug flag
# has been set.
sub debug_println
{
  my $string = shift;
  print $string . "\n" if( $debug_flag );
}


1;

