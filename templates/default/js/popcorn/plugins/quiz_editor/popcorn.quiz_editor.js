(function(Popcorn){
  
  var number_answers = 1;
  var MAX_ANSWERS = 5;
  
  var quiz_questions = new Array();
  var number_questions = 0;
  
  
  Popcorn.plugin("Quiz_Editor",  {
    _setup: function(options){
      this.on( "timeupdate", update_time_field);
      instance = this;
      
      document.getElementById("Submit_Button").addEventListener('click',validate_and_submit,false);
      add_answer();
      
    },
    
    start: function(event, options){
    },
    
    end: function(event, options){
    },
    
    toString: function( event, options ){
    }
  });
  
  function update_time_field()
  {
    document.getElementById('**timefield**').value = Math.floor(this.currentTime());
  }
  
  function add_answer(e)
  {
    var answer_row = document.getElementById('Answer_' + number_answers);
    var old_btn = document.getElementById("**button_container**");
    
    if(old_btn != null)
    {
      old_btn.innerHTML = "";
      old_btn.id = "";
    }
    
    var cell_A = document.createElement("td");
    var cell_B = document.createElement("td");
    var cell_C = document.createElement("td");
    var cell_D = document.createElement("td");
    
    var textfield= document.createElement("input");
    textfield.value = "";
    textfield.type = "text";
    textfield.name = "Answer_" + number_answers;
    
    var add_btn= document.createElement("button");
    add_btn.innerHTML = "Add Answer";
    add_btn.addEventListener('click', add_answer, false);
    
    var sol_element = document.createElement("input");
    sol_element.type = "checkbox";
    sol_element.name = "Sol_" + number_answers;
    
    cell_A.innerHTML = "Answer " + number_answers;
    cell_B.appendChild(textfield);
    cell_C.appendChild(sol_element);
    
    if(number_answers < MAX_ANSWERS)
    {
      cell_D.appendChild(add_btn);
      cell_D.id = "**button_container**";
    }
    
    answer_row.appendChild(cell_A);
    answer_row.appendChild(cell_B);
    answer_row.appendChild(cell_C);
    answer_row.appendChild(cell_D);
    
    number_answers += 1;
    
    console.log("Hah");
    e.preventDefault();
  }
  
  function remove_answer(e)
  {
    var answer_row = document.getElementById("Answer_" + number_answers);
    
    if(number_answers > 1)
    {
      answer_row.innerHTML = "";
      number_answers --;
    }
  }
  
  function validate_and_submit(e)
  {
    var frm = document.forms[0];
    
    if(Number(frm.elements["time"].value) == NaN)
      console.log("Timefield does not contain a number");
    
    else if(frm.elements["question"].value == "")
      console.log("User did not specify a question");
    
    else
    {
      var answers_given = 0;
      for(var i = 1; i < MAX_ANSWERS; i++) 
      {
        console.log("Answer_" + i);
        if(frm.elements["Answer_" + i] != null)
	{
	  if(frm.elements["Answer_" + i].value == "")
	  {
	    console.log("No answer specified");
	  }
	  else
	  {
	    answers_given++;
	  } 
	}
      }
      
      if(answers_given == number_answers - 1)
      {
        quiz_questions[ number_questions ] = new Object();
	
	quiz_questions[ number_questions ].time = Number(frm.elements["time"].value);
	quiz_questions[ number_questions ].question = frm.elements["question"].value;
	quiz_questions[ number_questions ].qtype = frm.elements["qType"].value;
	
	quiz_questions[ number_questions ].answers = new Array();
	
	var cur_ans = 0;
	for(var i = 1; i < MAX_ANSWERS; i++) 
	{
          if(frm.elements["Answer_" + i] != null)
	  {
	    quiz_questions[ number_questions ].answers[ cur_ans ] = new Object();
	    quiz_questions[ number_questions ].answers[ cur_ans ].text = frm.elements["Answer_" + i].value;
	    quiz_questions[ number_questions ].answers[ cur_ans++ ].is_sol = frm.elements["Sol_" + i].checked;
	  }
	}
	
      }
      else
      {
        console.log("Not enough answers specified: Found " + answers_given + ", needed " + number_answers);
      }
      
      console.log(quiz_questions[ number_questions ++ ]);
    }
  }
  
  function clear_form(e)
  {
  }
  
  function submit_to_server()
  {
  }
  
})(Popcorn);
