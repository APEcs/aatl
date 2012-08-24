window.addEvent("domready", function(){
   $('player').addEvent('timeupdate', time_update);
   console.log("Event Added");
});

/** Controls all the properties related to timing, such as when to fetch a quiz.
 *  It also sets the page content where appropriate.
 */
function time_update()
{
   $("time").set('text', "TIME UPDATED");
   console.log("TIME UPDATED");
}

/** Sends an Ajax request to the server, returning the quiz question
 *  in HTML format.
 */
function fetch_quiz(quiz_id)
{
   var fetch_request = new Request.HTML({ 
   				    url: api_request_path("materials", "request_quiz"),
				    onRequest: function(){
				        $('vid_overlay').set('class', 'overlay');
				        $('vid_overlay').fade('in');
				    },
				    onSuccess: function(respTree, respElems){
				        $('vid_overlay').adopt(respTree);
				    },
				    
			   });
    fetch_request.send("quiz_id="+quiz_id);
}
