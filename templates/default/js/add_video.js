window.addEvent("domready", prepare_form);

var file;
var progress_interval;

function prepare_form()
{
  // We'll use the modern upload functionality with a progress bar if we've got HTML 5
  if('FormData' in window)
  {
     var progress = $("progress_bar");
     
     var upload_request = new Request.File({
     		url: 	    api_request_path("materials", "upload/video"),
		
		onRequest:  function(){ 
			progress.setStyle('width', 10); 
			$("progress_text").set("html","Uploading... Please do not close the browser"); 
			$("debug_line").set("html","Requested..."); 
		//	$('video_form').getParent.set("html", "");
		},
		
		onProgress: function(event){
			var completion = parseInt( event.loaded / event.total * 100, 10 );
			progress.setStyle("width", completion.limit(0,100) + "%");
			$("debug_line").set("html", "Progress: " + completion.limit(0,100)+"%");
		},
		
		onComplete: function(resp){
			progress.setStyle("width", "0%");
			$("debug_line").set("html", resp);
			
			/* Now we should monitor the queue from this point onwards */
			progress_interval = window.setInterval( function(){monitor_progress(resp)}, 5000 );
			$("progress_text").set("html", "Converting... You can now safely close the browser");
			
		}
     });
     
     $("video_form").addEvent("submit", function(event){ 
     					// We don't want to refresh the page 
					if(event) event.preventDefault(); 
					
					// We need to explicitely add the video file to the upload request, otherwise it
					// won't work
					upload_request.append("video_file", document.getElementById("video_file").files[0]);
					upload_request.send();
					});
  }
  
  // We use the "iFrame hack" if the browser does not support HTML5
  // This could be replaced by Flash/SWF
  // This method does _not_ offer an upload progress bar, and I quite dislike it in general
  else
  {
     $("video_form").set("action", api_request_path("materials", "upload/video"));

     var iFrameReq = new iFrameFormRequest("video_form",{
  			   onRequest: function(){
			     $("debug_line").set("html", "Requested...");

			     file = $('video_file').get("value").replace(/^.*[\\\/]/, '');
			   },
			   onComplete: function(){
			     console.log("Completed...");
			   }
  		     });

     $("video_form").addEvent("submit", function(){ submit_form(); }); //iFrameReq.send(); });
  }
}

function monitor_progress(logfile)
{
  var progress_request = new Request({
  			   url: api_request_path("materials", "progress/video"),
			   onRequest: function(){
			   	$("debug_line").set("html", "Requesting Progress...");
			   },
			   onComplete: function(resp){
			        if("NOT_FOUND" != resp && resp != 0)
				{
			          console.log(resp);
			   	  $("progress_bar").morph({width: Math.floor(resp) + "%"});
				}
			   }
  		     });
   progress_request.send("logfile=" + logfile);
}

function submit_form()
{

  var file = document.getElementById('video_file').files[0];
  
  if( file )
  {
    var fileSize = Math.round(file.size * 100 / (1024 * 1024) / 100);
    console.log("FileSize: " + fileSize + "MB");
  }

}

function get_upload_progress()
{
  var upl_prog_request = new Request({
  			url: api_request_path("materials", "progress/video"),
			onRequest:  function(){
			  $("debug_line").set("html", "Uploading " + file);
			},
			onComplete: function(resp){
			   console.log(resp);
			},
			data: { filename: file }  
  		  });
  upl_prog_request.send();
}
