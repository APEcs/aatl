use File::Temp;

use IO::Socket;
use Protocol;
use Convert;

# We use multithreading to run our decoding in parrallel with the rest of the server
# This allows us to receive requests and add items to a queue regardless of whether
# we're currently dealing with a job. Queue size can be used to approximate waiting time
use threads;
use threads::shared;
use Thread::Queue;


# We need two protected variables - Queue and Status
# Status specifies if the processing thread is currently active
# Queue specifies the data structure
# Generally, if anything is in the queue, the Status variable should be Active.

our $PROCESSOR_STATUS :shared = 0;
our $PROCESSOR_QUEUE = Thread::Queue -> new();

# Start the server
run_server();

## @method $ run_server
# This method initialises and starts the server's listening thread.
sub run_server
{
  # Let's create a listener thread
  my $listener_thread = threads -> create('listener_thread');
  
  # Autoflush
  $| = 1;
  
  # Now run the listener thread
  $listener_thread -> join();
  
}

## @method $ listener_thread
# This method opens a socket listener on port
# 7070 on Localhost. 
sub listener_thread
{
  # We start off by creating a socket, and listening to it
  my $listener = new IO::Socket::INET(
		       LocalHost => '127.0.0.1',
		       LocalPort => '7070',
		       Proto => 'tcp',
		       Listen => 1,
		       Reuse => 1,
	             );
  die "Could not create socket: $!\n" unless $listener;

  $listener -> autoflush(1); 
  
  # We do not want to stop listening unless a manual shutdown occurs
  while( 1 )
  {
    # Listen to incoming connections
    my $incoming_connection = $listener -> accept();
    
    # Now we get the message that the client sends us
    my $incoming_data = <$incoming_connection>;
    
    # We can split the header and the packet up in a data array,
    # considering that they are tab seperated
    my @data_array = split("\t", $incoming_data);
    
    # The header will always be the first element, the packet
    # will always be the second element.
    my $header = $data_array[0];
    my $packet = $data_array[1];
    
    # Add it to the queue and invoke the processor thread if the queue is
    # no longer empty
    add_to_queue($packet) if($header eq $Protocol::CONVERT_VIDEO);
    invoke_processor_thread() if($STATUS == 0 && not queue_is_empty());
  }

  close( $listener );
}

## @method $ processor_thread
# The processor_thread method is used to process all the videos currently 
# in the queue. Videos may be added to the queue whilst this method is running.
# It is not advised to run this method from anywhere but the listener thread.
sub processor_thread
{
  # Notify the other threads that we are now actively processing the queue
  set_status(1);
#  my $video_converter = new Convert();

  # Not much else to do here than to loop until we've got an empty queue
  while( not queue_is_empty() )
  {
    # FETCH: We get the next message, but leave it in the queue
    my $next_message = peek_in_queue();
    
    print $next_message;
    
    # DECODE: Decode the message
    my $message_map = Protocol::string_to_map($next_message);
    
    # EXECUTE: Convert the video - This will lock the thread until it is done converting,
    # but the queue structure remains accessible, and as such this isn't a problem.
    my $video_converter = new Convert( max_file_size_mb => $message_map -> {"FILE_SIZE"}) if($message_map -> {"FILE_SIZE"} ne "");
    
    print "Converting: " . $message_map -> {"VIDEO_URL"};
    $video_converter -> convert_video( $message_map -> {"VIDEO_URL"}, $message_map -> {"OUTPUT_FORMAT"}, $message_map -> {"TEMP_FILE"} );
    
    sleep(2);
    
    # Notify any listeners that we've reached the final line
    open( MYFILE, ">>" . $message_map -> {"TEMP_FILE"});
    print MYFILE "EOF\n";
    close MYFILE;
    
    # Now that we're done with the message, we can safely pop it from the queue
    pop_from_queue();
  }
  
  # Notify the other threads that we are done and closing ourselves
  set_status(0);
}

## @method $ add_to_queue(ENCODED_MESSAGE)
# A method that adds a data packet to the protected queue. It serves as an abstraction of otherwise
# ugly code. It also allows for easily modifying the data structure that is used in the queue, if
# neccessary. 
sub add_to_queue
{
  print "Added to queue\n";
  $PROCESSOR_QUEUE -> enqueue(shift);
}

## @method $ peek_in_queue()
# Peeks at the next message in the queue, giving back the two variables stored in the list. 
# @return The method returns a Hash Map containing all information that was included in the message
sub peek_in_queue
{
  return $PROCESSOR_QUEUE -> peek(0);
}

## @method $ pop_from_queue()
# Pops a message from the shared queue and returns it
# @return The oldest message in the queue
sub pop_from_queue
{
  return $PROCESSOR_QUEUE -> dequeue();
}

## @method $ queue_is_empty()
# A method that checks if the protected queue is empty or not
# @return True if the queue is empty, False otherwise
sub queue_is_empty
{
  return $PROCESSOR_QUEUE -> pending() == 0;
}

## @method $ set_status(STATUS)
# Sets the status of the processor thread, to notify the listener thread
# of its activity. If the value is set to 1, the listener thread will know
# that the processor thread is currently active and processing a video.
# If it is 0, the listener thread will know that the processor thread currently
# doesn't exist, and will create one. Note that the processor thread will
# never poll once it runs out of data - it finishes and is destroyed.
sub set_status
{
  lock($PROCESSOR_STATUS);
  $PROCESSOR_STATUS = shift;
}

## @method $ is_active
# Checks if the processor thread is currently active. Returns True if it is, 
# False otherwise
sub is_active
{
  return $PROCESSOR_STATUS == 1;
}

## @method $ invoke_processor_thread()
# A helper method that invokes a processor thread after validating that the previous one was actually
# closed.
sub invoke_processor_thread()
{
  if(not is_active())
  {
    # Create the thread
    my $thread = threads -> create('processor_thread');
    
    # And detach it
    $thread -> detach();
  }
}
