var postlock = false;

/** Attempt to change the rating on a question or answer.
 *  This will contact the qaforum api and attempt to change the rating on the question
 *  or answer the rating is attached to.
 * 
 * @param element The element that triggered the rating change (should be an up or down arrow)
 */
function rate_toggle(element) 
{
    var full_id = element.get('id');
    var op      = full_id.substr(0, 3);
    var core_id = full_id.substr(4);

    var req = new Request({ url: api_request_path("qaforum", op),
                            onSuccess: function(respText, respXML) {
                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();
                                } else {
                                    var res = respXML.getElementsByTagName("rated")[0];

                                    var rup = res.getAttribute("up");
                                    if(rup == "set") {
                                        $('rup-'+core_id).addClass('rated');
                                    } else {
                                        $('rup-'+core_id).removeClass('rated');    
                                    }

                                    var rdown = res.getAttribute("down");
                                    if(rdown == "set") {
                                        $('rdn-'+core_id).addClass('rated');
                                    } else {
                                        $('rdn-'+core_id).removeClass('rated');    
                                    }

                                    var value = res.getAttribute("rating");
                                    if(value != null) {
                                        $('val-'+core_id).set('html', value);
                                    }
                                }
                            }
                          });
    req.send("id="+core_id);  
}


/** Allow the user to set or clear the best answer for a question.
 * 
 * @param element The element that triggered the best answer selection change.
 */
function best_toggle(element)
{
    var full_id = element.get('id');
    var core_id = full_id.substr(5);
    var base_id = full_id.substring(0, full_id.lastIndexOf('-') + 1);

    var req = new Request({ url: api_request_path("qaforum", "best"),
                            onSuccess: function(respText, respXML) {
                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();
                                } else {
                                    var res = respXML.getElementsByTagName("best")[0];

                                    var set = res.getAttribute("set");
                                    $$('div.bestctl').each(function(element) {
                                                               var eid = element.get('id');

                                                               if(eid == set) {
                                                                   element.addClass('chosen');
                                                               } else {
                                                                   element.removeClass('chosen');
                                                               }                                        
                                                           });
                                }
                            }
                          });
    req.send("id="+core_id);      
}


/** Convert a question subject and body to a form suitable for editing. This
 *  replaces the question subject with an input box, the body with a ckeditor 
 *  text area, and adds a 'reason' box and an 'edit' button.
 * 
 * @param qid    The ID of the question to convert to edit mode.
 * @param config The ckeditor configuration to use.
 */
function make_question_editable(qid, config) 
{
    // Fix up the click action on the edit button before doing anything else
    $('editbtn-q'+qid).removeEvent('click');
    $('editbtn-q'+qid).addClass('ctrldisabled');

    // Create the input elements needed to make the edit work
    var subject = new Element('input', { type: 'text',
                                         size: 70,
                                         maxlength: 100,
                                         value: $('subj-q'+qid).text,
                                         id: 'editsub-q'+qid
                                       });
    var message = new Element('div', { 'class': 'textwrapper'
                                     }).adopt(new Element('textarea', { rows: 5,
                                                                        cols: 80,
                                                                        html: $('qmsg-q'+qid).innerHTML,
                                                                        id: 'editmsg-q'+qid
                                                                      }));
    var submit = new Element('div', 
                             { 'class': 'newpost formsubmit' 
                             }).adopt([new Element('input', { type: 'text',
                                         size: 70,
                                         maxlength: 128,
                                         id: 'editwhy-q'+qid,
                                         title: whyfield_name,
                                         'class': 'whybox'
                                       }),
                                       new Element('img', { id: 'workspin-q'+qid,
                                                            style: 'opacity: 0',
                                                            src: spinner_url,
                                                            height: '16',
                                                            width: '16',
                                                            alt: 'working'}),
                                       new Element('input', { type: 'button',
                                                              id: 'edit-q'+qid,
                                                              name: 'edit-q'+qid,
                                                              'class': 'button blue',
                                                              onclick: 'edit_question(\''+qid+'\')',
                                                              value: editbtn_name })]);
    var container = new Element('div', {'class': 'editbox'}).adopt([message, submit]);
   
    
    // Attach them to the page in place of the original elements
    subject.replaces($('subj-q'+qid));
    container.replaces($('qmsg-q'+qid));
    CKEDITOR.replace('editmsg-q'+qid, { customConfig: config });
    new OverText($('editwhy-q'+qid));
    foo = 1;
}


/** AJAX function to take the contents of the editor fields for a question and ask
 *  the server to update the question. If the update succeeds, this replaces the edit
 *  fields with the returned content.
 * 
 * @param qid The ID of the question being updated.
 */
function edit_question(qid)
{
    if(postlock) return false;
    postlock = true;

    var req = new Request.HTML({ url: api_request_path("qaforum", "editq"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('workspin-q'+qid).fade('in');
                                     $('edit-q'+qid).removeEvents('click');
                                     $('edit-q'+qid).addClass('disabled');
                                 },
                                 onSuccess: function(respTree, respElems, respHTML) {
                                     var err = respHTML.match(/^<div id="apierror"/);
                                     
                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();

                                         $('workspin-q'+qid).fade('out');
                                         $('edit-q'+qid).removeClass('disabled');
                                         $('edit-q'+qid).addEvent('click', function() { edit_question(qid); });

                                     // No error, post was edited, the element provided should
                                     // be the updated <li>...
                                     } else {
                                         var tmp = new Element('div').adopt(respTree);
                                         tmp = tmp.getChildren()[0];

                                         var oldElem = $('qid-'+qid);
                                         oldElem.dissolve().get('reveal').chain(function() { CKEDITOR.instances['editmsg-q'+qid].destroy(); 
                                                                                             tmp.replaces(oldElem).reveal(); 
                                                                                             oldElem.destroy(); });
                                         
                                     }
                                     postlock = false;
                                 }
                               });
    req.post({qid: qid,
              subject: $('editsub-q'+qid).get('value'),
              reason: $('editwhy-q'+qid).get('value'),
              message: CKEDITOR.instances['editmsg-q'+qid].getData()
             });  
}


/** Attempt to delete a question. This will ask the server to delete the specified 
 *  question and if the entry is deleted the user is redirected to the question list.
 * 
 * @param qid The ID of the question to attempt to delete.
 */
function delete_question(qid)
{
    var req = new Request({ url: api_request_path("qaforum", "deleteq"),
                            onRequest: function() {
                                $('delbtn-q'+qid).addClass('working');
                                $('delbtn-q'+qid).getChildren('img')[0].fade('in');
                            },
                            onSuccess: function(respText, respXML) {
                                $('delbtn-q'+qid).getChildren('img')[0].fade('out').removeClass('working');
                                
                                var err = respXML.getElementsByTagName("error")[0];
                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();

                                // No error, post was deleted
                                } else {
                                    var reqpath = window.location.href;
                                    var blockpos = reqpath.indexOf('qaforum');
                                    if(blockpos != -1) {
                                        reqpath = reqpath.substring(0, blockpos + 7);
                                    }
                                    location.href = reqpath;
                                }
                            }
                          });
    req.send("qid="+qid);  
}

/** Add an answer to the specified question
 * 
 * @param questionid The ID of the question to add the answer to.
 */
function add_answer(questionid)
{
    if(postlock) return false;
    postlock = true;

    var req = new Request.HTML({ url: api_request_path("qaforum", "answer"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('answerspin').fade('in');
                                     $('newans').removeEvents('click');
                                     $('newans').addClass('disabled');
                                 },
                                 onSuccess: function(respTree, respElems, respHTML) {
                                     var err = respHTML.match(/^<div id="apierror"/);
                                     
                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();

                                     // No error, post was edited, the element provided should
                                     // be the new <li>...
                                     } else {
                                         $('answerheader').removeClass('noanswers');
                                         CKEDITOR.instances['new-answer'].setData('<p></p>');

                                         var tmp = new Element('div').adopt(respTree);
                                         tmp = tmp.getChildren()[0];
                                         tmp.setStyle("display", "none");

                                         if(sortmode == "updated"){
                                             tmp.inject($('answers'), 'top');
                                         } else {
                                             tmp.inject($('answers'), 'bottom');
                                         }
                                         tmp.reveal();

                                         var list = $('answers').getChildren();
                                         $('anscount').set('html', list.length);
                                     }
                                     $('answerspin').fade('out');
                                     $('newans').removeClass('disabled');
                                     $('newans').addEvent('click', function() { add_answer(questionid); });
                                     postlock = false;
                                 }
                               });
    req.post({id: questionid,
              message: CKEDITOR.instances['new-answer'].getData()
             }); 

    return false;
}


window.addEvent('domready', function() {
    $$('div.ratectl').each(
        function(element) {
            element.addEvent('click', function() { rate_toggle(element) });
        }
    );
    $$('div.bestctl').each(
        function(element) {
            element.addEvent('click', function() { best_toggle(element) });
        }
    );
});