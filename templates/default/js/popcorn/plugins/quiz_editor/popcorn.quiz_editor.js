window.addEvent("domready", function(){
				var popcorn = Popcorn( '#player' ), flag = true;
				popcorn.Quiz_Editor({
					mat_id: "0239" // Should specify the actual material ID here.
					});
                            });

(function(Popcorn){
  
  var current_time = 0;
  var question_list;
  var material_id = 1;
  
  var current_number_answers = 1;
  var instance;
  
  // The constructor for a popcorn plugin
  Popcorn.plugin("Quiz_Editor",  {
    _setup: function(options){
      this.on( "timeupdate", function(){ current_time = Math.floor(this.currentTime()); $("add_question").set("html","Add Question at: " + current_time + " seconds"); });
      instance = this;
      
      material_id = options.mat_id;
      
      $("submit_question").addEvent('click', submit_question);
      $("add_question").addEvent('click', request_form);// request_form);
      get_questions();
      
    },
    
    start: function(event, options){
    },
    
    end: function(event, options){
    },
    
    toString: function( event, options ){
    }
  });
  
  
  // Gets the questions from the database, and parses them into the table on the right hand side
  function get_questions()
  {
    var question_request = new Request({ url: api_request_path("materials", "request_edit_questions/video"),
    					 onRequest: function(){}, // Spinner here
					 onComplete: function(resp){
					   question_list = parse_xml_questions(resp);
					   update_questions_table();
					 }});
    question_request.send("mat_id=" + material_id);			 
  }
  
  // Should remove a question from the database, and parse the remaining questions into the table on the right hand side
  function delete_question(id)
  {
    var remove_request = new Request({ url: api_request_path("materials", "edit_remove_question/video"),
    				       onRequest: function(){},
				       onComplete: function(resp){
				       	   get_questions();
				       }
				    });
    remove_request("mat_id="+material_id+"&qid="+id);
  }
  
  /********************************************************************************************
  */// Form Stuff
  
  // This method will request the form and then fill it
  function edit_question(id)
  {
    request_form();
    
    // TODO:
    // Now populate the form with the information from question[id]
    console.log("editting question");
  }
  
  // This method will generate an empty form. Note that, for efficiency, the form is just a
  // hidden element. This means the user won't have to wait for a server response.
  function request_form()
  {
    $("quiz_form_wrapper").setStyle("visibility", "visible");
    $("number_answers_chkbox").addEvent("change", select_number_answers);
    $("form_time").set("value", current_time);
    
    $("submit_question").setStyle("visibility","visible");
    $("add_question").setStyle("visibility","hidden");
    
    // Pause the video
    instance.pause();
  }
  
  // This method will submit a new question to the database
  function submit_question(e)
  {
    $("quiz_form").set("action", api_request_path("materials","edit_submit_question/video"));
    var submit_request = new Form.Request("quiz_form", null, 
    				    { 
    				       onRequest: function(){}, // Spinner here
				       onComplete: function(resp, respXML){
				         console.log(respXML);
				       }
				    });
    submit_request.send();
  }
  
  // This method will remove the form after a question has been submitted or cancelled. 
  function remove_form(e)
  {
    // Clear all the element values
    
    // Hide the form
    $("quiz_form_wrapper").setStyle("visibility", "hidden");
    
    // Resume the video
    instance.play();
  }
  
  // This is an event method attached to the "Number of Answers" options box.
  // It's general enough to work with any number of answers greater than one.
  // In the actual form, I have currently restricted this to 5.
  function select_number_answers(e)
  {
     var new_number = parseInt(this.getElement(":selected").value);
     
     if(new_number < current_number_answers)
     {
        for(var i = new_number + 1; i <= current_number_answers; i++)
	{
	  $("answer_"+i).dispose();
	}
     }
     else if(new_number > current_number_answers)
     {
       for(var i = current_number_answers + 1; i <= new_number; i++)
       {
          var tr = new Element("tr", {id: 'answer_'+i});
	  var td_answer = new Element("td");
	  var td_issol  = new Element("td");
	  var td_feedbck= new Element("td");
	  
	  td_answer.grab(new Element("input", {type: "text", name: "answer_" + i}));
	  td_issol.grab(new Element("input", {type: "checkbox", name: "issol_" + i}));
	  td_feedbck.grab(new Element("input", {type: "text", name: "feedback_" + i}));
	  
	  tr.adopt(td_answer);
	  tr.adopt(td_issol);
	  tr.adopt(td_feedbck);
	  
          tr.inject("answer_" + (i-1), 'after');
       }
     }
     
     // Remember the current number of answers
     current_number_answers = new_number; 
  }
  
  /********************************************************************************************
  */// Helper Methods
  
  // Updates the questions table on the right hand side with the new questions stored in the questions_list array.
  // Note that whilst this one only displays the Time and Question, the question_list actually contains all the information
  // about all the questions in the table, including answers, booleans for solutions, feedback and ids. See parse_xml_question
  // for more information about the structure of the object, or just print it off with console.log
  function update_questions_table()
  {
    var qtable = $('questions_table');
    
    // Let's do it the easy way. Empty the body and refresh.
    qtable.set("html","<tr><td align='center'>Time</td><td align='center'>Question</td><td align='center'>Actions</td></tr>");
    
    var tbody = qtable.getElements("tbody")[0];
    
    for( var i = 0; i < question_list.length; i++ )
    {
      var qrow = new Element("tr");
      
      var time = new Element("td", { align: "center" });
      time.set("html", question_list[i].time);
      
      var txt  = new Element("td");
      txt.set("html", question_list[i].txt);
      
      qrow.adopt(time); qrow.adopt(txt); qrow.adopt(action_buttons(question_list[i].id));
      
      tbody.adopt(qrow);
    }
  }
  
  // Generates two action buttons (edit and remove) and attaches an event to them. 
  function action_buttons(id)
  {
    // Create the clickable elements, and attach an event to them
    var edit_link = new Element('a', { href: "javascript:void(0);",
    				       class: "edit_button",
				       events: {
				       	  click: function(){ edit_question(id) }
				       }
				     });
    var del_link  = new Element('a', { href: "javascript:void(0);",
    				       class: "remove_button",
				       events: {
				       	  click: function(){ delete_question(id) }
				       }
				     });
    
    // Insert the images
    edit_link.grab(new Element('img', { 
                                        src: template_path + "images/video/edit.png",
    					width: "15px",
					height: "20px" 
				      }
			       )
		   );
    del_link.grab(new Element('img',  { 
                                        src: template_path + "images/video/delete_ico.svg",
    					width: "15px",
					height: "20px" 
				      }
			       )
		   );
    
    var action_element = new Element('td', {align: "center"});
    action_element.grab(edit_link);
    action_element.grab(del_link);
    return action_element;
  }
  
  /********************************************************************************************
  */// XML Methods
  
  // This parses the questions xml provided to the method by the server into an array of objects.
  // The resulting object looks as follows:
  //
  /* question = {
                   id,
		   time,
		   txt,
		   type,
		   time,
		   answers = answer[]
   */           }
  /*
     answer   = {
                   id,
		   txt,
		   feedback,
		   is_solution
                }
   */
  function parse_xml_questions(xml)
  {
    var parser = new DOMParser();
    var doc    = parser.parseFromString(xml, 'text/xml');
    var qlist  = doc.getElementsByTagName("question");
    
    var questions = new Array();
    
    for(var i = 0; i < qlist.length; i++)
    {
       questions[i] = new Object();
       questions[i].id   = qlist[i].getElementsByTagName("question_id")[0].childNodes[0].nodeValue;
       questions[i].txt  = qlist[i].getElementsByTagName("question_text")[0].childNodes[0].nodeValue;
       questions[i].type = qlist[i].getElementsByTagName("question_type")[0].childNodes[0].nodeValue;
       questions[i].time = qlist[i].getElementsByTagName("time")[0].childNodes[0].nodeValue;
       
       var answers = qlist[i].getElementsByTagName("answers");
       
       if(answers.length > 0)
       {
         questions[i].answers = new Array();
	 for(var j = 0; j < answers.length; j++)
	 {
           questions[i].answers[j]             = new Object();
	   questions[i].answers[j].id          = answers[j].getElementsByTagName("answer_id")[0].childNodes[0].nodeValue;
	   questions[i].answers[j].txt         = answers[j].getElementsByTagName("answer_text")[0].childNodes[0].nodeValue;
	   questions[i].answers[j].feedback    = answers[j].getElementsByTagName("feedback")[0].childNodes[0].nodeValue;
	   questions[i].answers[j].is_solution = answers[j].getElementsByTagName("is_solution")[0].childNodes[0].nodeValue;
	 }
       } 
    }
    
    return questions;
  }
  
})(Popcorn);
