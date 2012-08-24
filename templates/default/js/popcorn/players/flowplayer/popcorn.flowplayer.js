// Flowplayer Plugin
// @author Jacobus Meulen

(function(){
  flowplayer_loaded = function( playerId ) {
    flowplayer_loaded[ playedId ] && flowplayer_loaded[ playerId ]();
  };
  
  flowplayer_loaded.seek = {};
  flowplayer_loaded.play = {};
  flowplayer_loaded.pause = {};
  flowplayer_loaded.loadProgress = {};

  Popcorn.player( "flow", {

    // Is the file supported? 
    _canPlayType: function( nodename, url ){
      return 1;
    },

    // Set up the variables, hooking HTML5 in with Flash
    _setup: function( options ){
      var media = this,
      	 	  flowObj,
		  flowContainer = document.createElement( "div" ),
		  currentTime = 0,
		  paused = true,
		  seekTime = 0,
		  seeking = false,
		  volumeChanged = false,
		  lastMuted = false,
		  lastVolume = 0,
		  height,
		  width;
//		  playerQueue = Popcorn.player.playerQueue();

      // Give our flowplayer container an ID
      flowContainer.id = media.id + Popcorn.guid();
      media.appendChild( flowContainer );

      // Set the height and width variables of our flowplayer
      width = media.style.width ? "" + media.offsetWidth : "560";
      height = media.style.height ? "" + media.offsetHeight : "560";

      // Setup the initialisation environment
      var flowplayerInit = function() {

	var flashvars,
            params,
	    attributes = {},
	    src = media.src,
	    toggleMuteVolume = 0,
	    loadStarted = false;


	flowplayer_loaded[ flowContainer.id ] = function() {
          flowObject = document.getElementById( flowContainer.id );

	  // Implementing the seek event, taking time as an argument
	  flowplayer_loaded.seek[ flowContainer.id ] = function( time ) {
	    if( time.seconds !== currentTime ) {
	      seeking = true;
	      media.dispatchEvent( "seeking" );
	      currentTime = time.seconds;
	      seeking = false;
	      media.dispatchEvent( "timeupdate" );
	      media.dispatchEvent( "seeked" );
	    }
	  };

	  // Implement the play event
	  // This dispatches the play and playing events,
	  // updates the time and sets paused to false
	  flowplayer_loaded.play[ flowContainer.id ] = function() {
	    paused = false;
	    media.dispatchEvent( "play" );
	    media.dispatchEvent( "playing" );
	    timeUpdate();

//	    playerQueue.next();
	  };

	  // When we pause we should dispatch an event and
	  // set the paused variable
	  flowplayer_loaded.pause[ flowContainer.id ] = function() {
	    paused = true;
	    media.dispatchEvent("pause");

//	    playerQueue.next();
  	  };

	  // Load the progress bar from the player
	  flowplayer_loaded.loadProgress[ flowContainer.id ] = function( progress ) {
	    if( !loadStarted ){
	      loadStarted = true;
	      media.dispatchEvent( "loadstart" );
	    }
	    if( progress.percent === 100 ){
	      media.dispatchEvent( "canplaythrough" );
	    }
  	  };

	  // Now add the previous event listeners to the flow API
	  flowObject.api_addEventListener( "seek", "flowplayer_loaded.seek." + flowContainer.id);
	  flowObject.api_addEventListener( "play", "flowplayer_loaded.play." + flowContainer.id);
	  flowObject.api_addEventListener( "pause", "flowplayer_loaded.pause." + flowContainer.id);
	  flowObject.api_addEventListener( "loadProgress", "flowplayer_loaded.loadProgress." + flowContainer.id);

	  // The following functions can

	  // Dispatching the time update event
	  var timeUpdate = function() {
	    if( !media.paused ) {
	      currentTime = flowObject.api_getCurrentTime();
	      media.dispatchEvent( "timeupdate" );
	      setTimeout( timeUpdate, 10 );
	    }
   	  };

	  // Returns true if the video is muted
	  var isMuted = function() {
	    return flowObject.api_getVolume() === 0;
	  };

	  // Dispatches a volume update event
	  var volumeUpdate = function(){
	    var muted = isMuted(),
		vol = flowObject.api_getVolume();


	    // If the muted state has changed, we modify that accordingly  
	    if( lastMuted !== muted ){
	      lastMuted = muted;
	      media.dispatchEvent( "volumechange" );
	    }

	    // If the volume has changed, we'll dispatch an event
	    if( lastVolume !== vol ){
	      lastVolume = vol;
	      media.dispatchEvent( "volumechange" );
	    }

	    setTimeout( volumeUpdate, 250);
	  };

	  // Set the play functionality
	  media.play = function() {

	    // If we're playing now, we're no longer paused
	    paused = false;

	    // Handle queues
	//    playerQueue.add(function() {
	//      if( flowObject.api_paused() )
//		flowObject.api_play();
//	      else
//		playerQueue.next();
//	    });
	  };

	  // Handle pausing
	  media.pause = function() {

	    // We're pausing the video
	    paused = true;

	    // And we deal with queues
//	    playerQueue.add(function() {
	//      if( !flowObject.api_paused() )
	//	flowObject.api_pause();
	//      else
	//	playerQueue.next();
	//    });
	  };

	  // Define the seeking property, and set its get function
	  Popcorn.player.defineProperty( media, "seeking", {
	    get: function() {
	      return seeking;
	    }
	  });

	  // Define the CurrentTime property and set its get and set functions
	  Popcorn.player.defineProperty( media, "currentTime", {
	    set: function(){
	      if (!val)
		return currentTime;

	      flowObject.api_seekTo( +val );
	      return currentTime;
	    },

	    get: function(){
	      return currentTime;
	    }
	  });

	  // Define the Paused property
	  Popcorn.player.defineProperty( media, "paused", {
	    get: function(){
	      return paused;
	    }
	  });

	  // Define the mute function
	  Popcorn.player.defineProperty( media, "muted", {
	    set: function( val ){
	      if( isMuted() !== val ){
		if( val ) 
		{
	          toggleMuteVolume = flowObject.api_getVolume();
		  flowObject.api_setVolume( 0 );
		}
		else
		{
	          flowObject.api_setVolume( toggleMuteVolume );
		}
	      }
	    },

	    get: function(){
	      return isMuted();
	    }
	  });

	  // Define the volume function
	  Popcorn.player.defineProperty( media, "volume", {
	    set: function( val ){
	      if( !val || typeof val !== "number" || (val < 0 || val > 1) )
		return flowObject.api_getVolume() / 100;

	      if( flowObject.api_getVolume() !== val )
	      {
		flowObject.api_setVolume( val * 100 );
		lastVolume = flowObject.api_getVolume();
		media.dispatchEvent( "volumechange" );
	      }

	      return flowObject.api_getVolume() / 100;
 	    },

	    get: function() {
	      return flowObject.api_getVolume() / 100;
	    }
	  });

	  media.duration = flowObject.api_getDuration();
	  media.dispatchEvent( "durationchange" );
	  media.dispatchEvent( "loadedmetadata" );
	  media.dispatchEvent( "loadeddata" );

	  volumeUpdate();
	  media.readyState = 4;
	  media.dispatchEvent( "canplaythrough" );
	};

	// Load in the flashvars
	flashvars = {
          clip_id: 10,
	  api: 1,
	  js_swf_id: flowContainer.id
	};
	Popcorn.extend( flashvars, options );

	// Load in the params
	params = {
          allowscriptaccess: "always",
	  allowfullscreen: "true",
	  wmode: "transparent"
	};
	swfobject.embedSWF("flowplayer-3.2.12.swf", flowContainer.id,
      			   width, height, "9.0.0", "expressInstall.swf",
			   flashvars, params, attributes);
      };

      if( !window.swfobject )
	Popcorn.getScript("//ajax.googleapis.com/ajax/libs/swfobject/2.2/swfobject.js", flowplayerInit);
      else
	flowplayerInit();

    }
  });
})();
