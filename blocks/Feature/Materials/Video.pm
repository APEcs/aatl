## @file
# This file contains the implementation of the AATL Video feature class.
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

## @class Feature::Materials::Video
# This class encapsulates the view and control functionality for the video
# and video quiz features. 
package Feature::Materials::Video;

use strict;
use base qw(Feature::Materials);

use System::Materials;
use System::Materials::Video;

use XML::Simple;
use File::Tail;

use Data::Dumper;

# ==============================================================================
#   Create

## @method $ new(%args)
# Construct the Video feature, initialising the required variables, and set
# up the environment.
# 
# @param args A hash of values to initialise the object with. See the Block
#	      docs for more information.
# @return A new instance of the Feature::Video class on success, undef otherwise
sub new
{
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self	 = $class -> SUPER::new(@_) or return undef;
    
    # Create a new Video Model to work with
    $self -> {"materials::video"} = System::Materials::Video -> new(
    					dbh 	 => $self -> {"dbh"},
					settings => $self -> {"settings"},
					logger	 => $self -> {"logger"},
					module   => $self -> {"module"},
					roles    => $self -> {"system"} -> {"roles"},
					metadata => $self -> {"system"} -> {"metadata"},
					courses  => $self -> {"system"} -> {"courses"})
          or return SystemModule::set_error("Video initialisation failed: ".$System::Materials::Video::errstr);
    
    return $self;
}

# ==============================================================================
#   Quiz Viewing

## @method $ build_quiz
#  This method builds the layout and the content of a given quiz question, specified
#  by the CGI object. It renders the answers, the question and the buttons that are
#  required by the user.
#  @return A completed HTML Template containg all the relevant information.
sub build_quiz
{
    my $self = shift;
    # Get the quiz id, which is passed
    my $question_id = $self -> {"cgi"} -> param("quiz_id");

    # Gets the quiz from the database
    my $question  = _get_question_by_id($self, $question_id);
    my $answers   = _get_answers_by_qid($self, $question_id);
    
    my $quiz = { question_nr  => "1",
    		 question_txt => $question -> {"question_text"},
		 question_id  => $question_id,
		 answer_type  => $question -> {"question_type"},
		 answers      => $answers
	       };

    # We generate the different answers
    my $answers_html = "";
    for (@{$quiz -> {"answers"}})
    {
        $answers_html = $answers_html . "<a href='javascript:void(0)' 
					      id='answer_".$_ -> {"answer_id"}."'> 
					 <input type='" . $quiz->{"answer_type"} . "' 
					        name='answer' 
						id='checkbox_". $_->{"answer_id"}."' 
						value='".$_->{"answer_id"}."'>".
					  $_ -> {"answer_text"}."</a><br/>";
    }
    
    my $buttons = "<button id='submit'>Submit</button>
    		   <button disabled='disabled' id='continue'>Continue</button>
		   <button id='skip'>Skip</button>";
    
    return $self -> {"template"} -> load_template("feature/video/quiz.tem", {
    							"***question_number***" => 1, # This should be modified accordingly
							"***question***"        => $quiz -> {"question_txt"},
							"***question_id***" 	=> $question_id,
							"***answers***" 	=> $answers_html,
							"***feedback***"	=> "",
							"***buttons***"		=> $buttons
    					   		});
}

## @method $ validate_answers
#  Validate answers checks the user answers against those specified by the lecturer
#  It sends the appropriate feedback back if the user specified an incorrect answer.
#  @return The string CORRECT if the answer was correct, and INCORRECT followed by
#	   tab, followed by a message with newline seperated feedback if the answer was incorrect
sub validate_answers
{
    my $self = shift;
    
    my $q_id = $self -> {"cgi"} -> param("quiz_id");
    
    my $solutions = _get_feedback_by_qid($self, $q_id);
    my @selected_answers = $self -> {"cgi"} -> param("answer");
    
    my $feedback = "";
    foreach my $answer (@selected_answers)
    {
      unless( $solutions -> {"$answer"}{"is_solution"} )
      {
        $feedback = $feedback . $solutions -> {"$answer"}{"feedback"} . "\n";
      }
    }
    
    
    return "CORRECT" if ($feedback eq "");
    
    return "INCORRECT\t$feedback";
}

# ==============================================================================
#   Video Uploading & Converting
sub upload_video
{
    my $self = shift;
    
    # We check for the user permissions
    
    # Now that we've validated permissions, we can grab the data and store it 
    # on the server
    my $video = System::Materials::Video -> upload_video($self, $self -> {"cgi"}, "video_file", "test");
    
    # Create a temporary file to log the data in
    
    my $log_file = "/tmp/test.log";
    
    #########################################################
    ## Now we prepare for converting the video
    
    my %args     = ( VIDEO_URL => $video,
    		     FILE_SIZE => 50,
		     TEMP_FILE => $log_file);
    
    my $args_mp4 = System::Materials::Video -> map_to_string( %args, OUTPUT_FORMAT => "mp4");
    my $args_ogg = System::Materials::Video -> map_to_string( %args, OUTPUT_FORMAT => "ogg");
    
    # Finally, we dispatch the video to the server
    System::Materials::Video -> dispatch_video($self, $args_mp4);
    System::Materials::Video -> dispatch_video($self, $args_ogg);
    
    # We can now make an entry into the database to accomodate the video information
    
    return $log_file;
}

## @method $ get_progress
#  Gets the progress of the video conversion from the log file. On the client side we can
#  assume that if we get a NOT_FOUND error when our progress is still 0, the conversion hasn't
#  started. If on the other hand we get a NOT_FOUND error when we've already seen progress,
#  the video has finished converting.
#  @return The progress in percentage and NOT_FOUND if the file doesn't exist.
sub get_progress
{
    my $self = shift;
    
    my $log_file = $self -> {"cgi"} -> param("logfile");
    
    return "NOT_FOUND" unless ( -e $log_file );
    
    # We can now open the file for reading
    my $filehandle = File::Tail -> new( $log_file ) 
        or return 0;
    #	or return $self -> self_error("Could not open $log_file for reading: $!");

    # We read the last line
    my $progress_line; my $timeout = 500;
    while(not defined ($progress_line = $filehandle -> read) && $timeout > 0){ $timeout--; };
    return "0" unless(defined($progress_line));
    
    # Return a special symbol if we're done processing
    return 100 if( $progress_line eq "EOF\n" );
    
    # Reduce the number of whitespaces to make the string parsable
    $progress_line =~ s/\h+/ /g;
 
    # Now we can split the string on white spaces
    my @progress_data = split( " ", $progress_line );

    # Temporary line to accomodate for the lack of structure
    my $video_info = { length_in_seconds => 235 };
    
    if(defined($video_info -> {"length_in_seconds"})) 
    {
      my $progress = ($progress_data[9] / $video_info -> {"length_in_seconds"});
      return ($progress * 100) . "\n";
    }

}

# ==============================================================================
#   Quiz Creation & Editing

# COMING SOON

# ==============================================================================
#   Interface

sub block_display
{
    my $self = shift;
    return $self -> {"template"} -> load_template("feature/video/upload_form.tem",
    						  {"***form_properties***" => "method='post' enctype='multipart/form-data'",
						  "***file_id***" 	  => "video_file"});
    
    return $self -> {"template"} -> load_template("feature/video/video.tem",{
						    "***video_sources***" => "<source src='../../../../~meulenj9/video/hello.ogg'>"
						  });
}

sub page_display
{
    my $self = shift;
    
    # Now we check for api operations
    my $apiop = $self -> is_api_operation();
 
    if(defined $apiop)
    {  
       if($apiop eq "get_time_id_list")
       {
           # This returns a sorted list of time:id pairs, which specify the times at 
	   # at which a new quiz may be requested.
	   my $questions = _get_sorted_question_list($self, 1);
	   
	   # This is to force XML::Simple into the right behaviour. Feel free to improve/change it.
	   for(@{$questions})
	   {
	     $_ -> {"id"}   = [ $_ -> {"question_id"} ];
	     $_ -> {"time"} = [ $_ -> {"time"} ];
	   }
	   
	   return XMLout({question => $questions }); 
       }
       elsif($apiop eq "request_quiz")
       {
           # This function returns the quiz (without solutions and feedback)
	   return build_quiz($self);
       }
       elsif($apiop eq "skip_quiz")
       {
           # We can log it here if the user skips
	   return "SUCCESS";
       }
       elsif($apiop eq "submit_quiz")
       {
           # This function validates the answers given by the user. If they're
	   # correct, a CORRECT response is given, which can be ignored by javascript.
	   # Otherwise, an INCORRECT response is given, which (seperated by tabs) gives
	   # the feedback. This would be the place to log information about the user.
	   return validate_answers($self);
       }
       else
       {
           # The functionality that follows is only allowed to be performed by users with
	   # special priviliges, such as lecturers. 
	   
	   # First validate if the user has permissions to actually perform any of these
	   # actions
	   
	   
	   # Now we can deal with the different actions
	   if($apiop eq "upload")
	   {
	       return upload_video($self);
	   }
	   elsif($apiop eq "progress")
	   {
	       return get_progress($self);
	   }
	   else
	   {
	       # Log this as potential mallicious access. Log the API operation, userid, material id.
               return "Invalid Operation!!!!!!!!!!!!!!!!!!!!!!!!";
	   }
       }
    }
    
    
    return "Test";
}

## ============================================================================================
#    Internals

## @method private $ _get_sorted_question_list($mat_id)
# This method retrieves a sorted time:question_id list. The question_id can be used to retrieve 
# the appropriate data from the database without storing any crucial information on the client-side.
# This helps reduce or eliminate the amount of possible 'cheating' that can be done with the system.
# 
# @param mat_id The material id that is associated with the video that the user is viewing
# @return Returns an Array Reference containing the data on a successful operation, undef otherwise.
sub _get_sorted_question_list
{
    my $self   = shift;
    my $mat_id = shift;
    
    $self -> clear_error();
    
    my $sortedq_query = $self -> {"dbh"} -> prepare("SELECT time, question_id
    						     FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material::video_questions"} ."`
						     WHERE material_id = ?
						     ORDER BY time ASC");
    $sortedq_query -> execute($mat_id) 
       or return $self -> self_error("Unable to execute quiz question query: " . $self -> {"dbh"} -> errstr);
    
    return $sortedq_query -> fetchall_arrayref({});
}


## @method private $ _get_question_by_id($question_id)
# This method returns the question type and text based on the supplied ID. The results do not include
# answers or solutions in order to compensate both for secure handling of the data, and the ability to
# supply any number of answers to a given question. 
#
# @param question_id The ID of the question that we're trying to retrieve.
# @return Returns the question_type and question_text as a hashref if the operation was successful, undef otherwise
sub _get_question_by_id
{
    my $self   = shift;
    my $q_id   = shift;
    
    $self -> clear_error();
    
    my $question_query = $self -> {"dbh"} -> prepare("SELECT question_type, question_text
    						      FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material::video_questions"} ."`
						      WHERE question_id = ?");
    $question_query -> execute($q_id)
    	or return $self -> self_error("Unable to execute quiz question query: " . $self -> {"dbh"} -> errstr);
    
    return $question_query -> fetchrow_hashref();
}


## @method private $ _get_answers_by_qid($question_id)
# Gets all the answers from the database that relate to the specified question id.
# Solutions and feedback are not included, and need to be retrieved seperately to further reduce the amount of
# freedom that the users have in modifying the inputs and outputs of the system.
#
# @param question_id The question id associated with the answers that we're trying to retrieve
# @return Returns the answer_id and answer_text if the operation was successful, undef otherwise.
sub _get_answers_by_qid
{
    my $self   = shift;
    my $q_id   = shift;
    
    $self -> clear_error();
    
    my $answers_query = $self -> {"dbh"} -> prepare("SELECT answer_id, answer_text
    						     FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material::video_answers"} ."`
						     WHERE question_id = ?");
    $answers_query -> execute($q_id)
    	or return $self -> self_error("Unable to execute quiz question query: " . $self -> {"dbh"} -> errstr);
    
    return $answers_query -> fetchall_arrayref({});
}

## @method private $ _get_feedback_by_qid($question_id)
# Gets all the feedback from the database that are associated with the given question id.
# This includes whether or not the given question was correct as is_solution, the answer id
# and the feedback that it belongs to, and the feedback text itself.
# 
# @param question_id The question id that specifies the feedback we're trying to retrieve
# @return Returns a hashref with "answer_id" as key and entries for "feedback" and "is_solution" if successful.
#	  undef otherwise.  
sub _get_feedback_by_qid
{
    my $self = shift;
    my $q_id = shift;
    
    $self -> clear_error();
    print STDERR "QID: " . $q_id;
    my $solutions_query = $self -> {"dbh"} -> prepare("SELECT answer_id, is_solution, feedback
    						       FROM `".$self -> {"settings"} -> {"database"} -> {"feature::material::video_answers"} ."`
						       WHERE question_id = ?");
    $solutions_query -> execute($q_id)
    	or return $self -> self_error("Unable to execute quiz question query: " . $self -> {"dbh"} -> errstr);
    
    return $solutions_query -> fetchall_hashref("answer_id");
}

1;
