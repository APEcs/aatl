/*
* Flext - A Mootools Based Flexible TextArea Class
* version 1.1 - for mootools 1.2
* by Graham McNicoll
* 
* Copyright 2008-2009 - Education.com
* License:	MIT-style license.
*
* Modified 1 May 2011 by Chris Page.
* 
* Features:
*  - Grows text areas when needed
*  - Can set a max height to grow to
*  - Text input emulation (enter can submit form, instead of new line)
*
* Usage:
*
*  include the source somewhere on your page. Textareas must have the class name: 'flext' 
*  for the class to watch them. Use additional class names to trigger features.
* 
*   'growme' -  grow the text area
*   'maxheight-[num]' - the max height to grow in pixels (replaces [num] )
*   'stopenter' - stop the enter key
*   'entersubmits' - submit the form when enter is pressed
*
* Note that this includes some significant changes from the 'official' release
* available at https://github.com/Auz/Flext In particular:
* 
* - Removed growparent and ghosting facilities, as they are not needed.
* - changes to resizeIt to make it less of a mess.
* 
* VERY IMPORTANT: Any textarea this is attached to MUST have `padding: 0px;` set
*                 or it will break in Opera, and potentially other browsers that
*                 include padding when getScrollSize() is used. With padding set
*                 to zero, this should be portable.
*/

var Flext = new Class({
	Implements: Options,
	options: {
		aniTime: 300, 					//int (ms) - grow animation time
		maxHeight: 0,					//int (pixels) - one way to set a max height, if you dont set it via the class.
		defaultMaxHeight: 1000,			//int (pixels) - if not otherwise set, this is the max height
		parentDepth: 6,				//int - how many levels up should to check the parent el's height.
		//trigger classes:
		growClass: 'growme',					//string (class name)- grow the text area
		enterStoppedClass: 'stopenter',			//string (class name)- stop the enter key
		enterSubmitsClass: 'entersubmits'			//string (class name)- submit the form when enter is pressed
	},
	initialize: function(el, options) {
		this.setOptions(options);
		
		this.el = document.id(el); //the textarea element.
		
		//by default, we will do nothing to the text area unless it has the class...
		this.autoGrow = el.hasClass(this.options.growClass);
		this.stopEnter = el.hasClass(this.options.enterStoppedClass);
		this.enterSubmits = el.hasClass(this.options.enterSubmitsClass);
		
		//initialize, and add events:
		if(this.autoGrow) {
			this.resizer = new Fx.Tween(this.el, {duration: this.options.aniTime});
			this.getMaxSize();
			this.reachedMax = false;
			this.startSize = this.origSize = this.el.getSize().y;
			this.vertPadding = this.el.getStyle('padding-top').toInt()+this.el.getStyle('padding-bottom').toInt()+this.el.getStyle('border-top').toInt()+this.el.getStyle('border-bottom').toInt();
			this.el.setStyle('overflow', 'hidden');
			this.el.addEvents({
				'keyup': function(e) {
					this.checkSize(e);
				}.bind(this),
				'change': function(e) {
					this.checkSize(e);
				}.bind(this),
				'click': function(e) {
					this.checkSize(e);
				}.bind(this)
			});
		
			//get inital state:
			this.checkSize();
		}
		//watch this text area: keydown
		if(this.stopEnter) {
			this.el.addEvent('keydown', function(e) {
				if(e.key == 'enter') {
					e.stop();
					if(this.enterSubmits) {
						this.submitForm();
					}
				}
			}.bind(this));
		}
	},
	getMaxSize: function() {
		this.maxSize = this.options.maxHeight;
		if(this.maxSize == 0) {
			var testmax = this.el.className.match(/maxheight-(\d*)/);
			if(testmax) {
				this.maxSize = testmax[1];
			}
			else {
				this.maxSize = this.options.defaultMaxHeight; //if one forgets to set a max height via options or class, use a reasonable number.
			}
		}
	},
	checkSize: function(e) {
		var theSize = this.el.getSize();
		var theScrollSize = this.el.getScrollSize();
		if(navigator.userAgent.toLowerCase().indexOf('chrome') > -1) { 
               var checksize = theScrollSize.y; 
        }
		else var checksize = (theScrollSize.y+this.vertPadding);
		if(checksize > theSize.y) {
			//we are scrolling, so grow:
			this.resizeIt(theScrollSize.y);
		}
	},
	resizeIt: function(newSize) {

		if((newSize+this.vertPadding) > this.maxSize && !this.reachedMax) {
			//we've reached the max size, grow to max size and make textarea scrollable again:
			newSize = this.maxSize;
			this.el.setStyle('overflow', '');
			this.resizer.start('height', newSize);

			//remember that we've reached the max size:
			this.reachedMax = true;
		}
		if(!this.reachedMax) {
			//grow the text area:
			var increasedSize = newSize - this.startSize;
			if(increasedSize < 0) increasedSize = 0;


			this.startSize = newSize;
			this.resizer.start('height', newSize);
		}
	}, 
	submitForm: function() {
		var thisForm = this.el.getParent('form');
		if(thisForm) {
			var formName = thisForm.get('name');
			document[formName].submit();
			
		}
	}
});


//watch the text areas:
window.addEvent('domready', function() {
	$$('textarea.flext').each(function(el, i) {
		new Flext(el); 
	});
});

