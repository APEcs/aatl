/**
 */
document.addEventListener( "DOMContentLoaded", function() {
						var popcorn = Popcorn( "#player" ), flag = true;
						popcorn.QuestionMaster({
							mat_id: "0239"
							});
 					  }, false);

(function(Popcorn){
  // Popcorn
  var instance;
  
  // Quiz Variables
  var mat_id;
  var time_id_list;
  
  /**
   * Popcorn.plugin is an interface to the Popcorn Library. It registers
   * this class as a plugin in the API, and can then be used as a function
   * of the API.
   */
  Popcorn.plugin("QuestionMaster", {
    _setup: function(options){
       initialise(this, options);
    },
    
    start: function(event, options){
    },
    
    end: function(event, options){
    },
    
    toString: function( event, options ){
    }
  });
  
  /** Initialise the variables, and fetch the required information
   */
  function initialise(self, options)
  {
      instance = self;
      mat_id = options.mat_id;

      instance.on( "timeupdate", time_update);      
      
      var fetch_qlist = new Request({
       				     url: api_request_path("materials", "get_time_id_list/video"),
				     onSuccess: function(respText, respXML){
				     	  console.log(respText);
				     	  process_xml_qlist(respText);
				     }
      			    });
			    
      fetch_qlist.send("matid=" + mat_id);
  }

  /** Controls all the properties related to timing, such as when to fetch a quiz.
   *  It also sets the page content where appropriate.
   */
  function time_update()
  {
     var time = Math.floor(instance.currentTime());
     
     var i = 0;
     while( i < time_id_list.length && time_id_list[i].time < time ) i++;
     
     if( i != time_id_list.length && time_id_list[i].time == time && time_id_list[i].asked == false)
     {
       time_id_list[i].asked = true;
       fetch_quiz(time_id_list[i].id);
     }
     
     $("time").set('text', time);
  }
  
  /** Sends an Ajax request to the server, returning the quiz question
   *  in HTML format.
   */
  function fetch_quiz(quiz_id)
  {
     var fetch_request = new Request.HTML({ 
   				      url: api_request_path("materials", "request_quiz/video"),
				      onRequest: function(){
				          $('vid_overlay').set('class', 'overlay');
					  instance.pause();
				          $('vid_overlay').fade('in');
				      },
				      onSuccess: function(respTree, respElems){
				          $('vid_overlay').adopt(respTree);
					  
					  $('form_'+quiz_id).getElements("a").each( 
					  	function(el){ 
							el.addEvent("click", function(){ toggle_checkbox(el.id.substring(7)); } );
						});
					  
					  $('submit').addEvent('click', function(){submit_answers(quiz_id)}, false);
					  $('continue').addEvent('click', function(){continue_video(quiz_id)}, false);
					  $('skip').addEvent('click', function(){skip_quiz(quiz_id)}, false);
				      },
			     });
      fetch_request.send("quiz_id="+quiz_id);
  }
  
  /** Submits the quiz, performs server-side validation, and sets the appropriate feedback
   *  and parameters.
   */
  function submit_answers(q_id)
  {
  
     var submit_request = new Form.Request("form_" + q_id, "feedback",{
				  extraData: {
				       quiz_id: q_id
				  },
				  resetForm: false,
     				  requestOptions: {
     				       url: api_request_path("materials", "submit_quiz/video"),
				       
				       onRequest: function(){
					   $('loading').set('html','Submitting... Please Wait');
					   $('loading').adopt(new Element('img#spinner'));
					   $('spinner').set('src', '../templates/default/images/spinner.gif');
				       },

				  },
				  
				  onSuccess: function(updatedEl, respTree, respElems, respHTML){
				      $('loading').set('html','');
				      
				      var data = tss_to_array("" + respHTML);
				      
				      if(data[0] != "CORRECT")
				      {
				   	   $('feedback').set('html', data[1]);
				      }
				      
				      $('submit').set('disabled','disabled');
				      $('continue').set('disabled','');
				      $('skip').set('disabled','disabled');
				      
				  }
     			      });
     submit_request.send();
			      
  }
  
  /** A helper method to toggle the checkbox and radio buttons when the answer text is clicked instead
   *  of the box
   */
  function toggle_checkbox(answer_id)
  {
     $('checkbox_' + answer_id).checked = !$('checkbox_' + answer_id).checked;
  }
  
  /** Skips the quiz, enabling the buttons
   *
   */
  function skip_quiz(quiz_id)
  {
     var skip_request = new Request.HTML({
     				     url: api_request_path("materials", "submit_quiz/video"),
				     onRequest: function(){
				     },
				     onSuccess: function(respTree, respElems){
				     }
     			    });
     skip_request.send("quiz_id="+quiz_id);
     
     continue_video(quiz_id);
  }
  
  /** Continues the video from where it left off before the quiz.
   *  Removes the overlay and its contents.
   */
  function continue_video(quiz_id)
  {
     $('vid_overlay').set('class','');
     $('vid_overlay').set('html', '');
     instance.play();
  }
  
  
  /************************************************************************************************
   **
   ************************************************************************************************/
   
  /** 
   * 
   */
  function tss_to_array(tss)
  {
     return tss.split('\t');
  }
  
  /** Using the given XML Time to Id list, this method parses it into an easier and cleaner to use
   *  (global) javascript object.
   */
  function process_xml_qlist(xml)
  {
     var parser = new DOMParser();
     var doc = parser.parseFromString(xml,'text/xml');
     var qlist = doc.getElementsByTagName("question");
     
     time_id_list = new Array();
     
     for(var i = 0; i < qlist.length; i++)
     {
        var id   = qlist[i].getElementsByTagName("id")[0].childNodes[0].nodeValue;
	var time = qlist[i].getElementsByTagName("time")[0].childNodes[0].nodeValue;
	
	time_id_list[i] = new Object();
	time_id_list[i].time = time;
	time_id_list[i].id   = id; 
	time_id_list[i].asked= false;
     }
  } 
  
})(Popcorn);
