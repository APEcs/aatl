var postlock = false;
var apostlock = false;
var cpostlock = false;
var flaglock  = false;

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
    req.send("cid="+courseid+"&id="+core_id);
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
    req.send("cid="+courseid+"&id="+core_id);
}


/** Allow the user to set or clear their 'helpful' status for a comment.
 *
 * @param full_id A string containing the mode (qid, aid), the id of the
 *                question or answer the comment is attached to, and the
 *                id of the comment itself.
 */
function helpful_comment(full_id)
{
    var comm_id = full_id.substr(full_id.lastIndexOf("-") + 1);

    var req = new Request({ url: api_request_path("qaforum", "chelpful"),
                            onSuccess: function(respText, respXML) {
                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();
                                } else {
                                    var res = respXML.getElementsByTagName("helpful")[0];

                                    var set = res.getAttribute("set");
                                    var rating = res.getAttribute('rating');

                                    $('helpful-'+comm_id).set('html', rating);
                                    if(rating != '0') {
                                        $('helpful-'+comm_id).fade('in');
                                    } else {
                                        $('helpful-'+comm_id).fade('out');
                                    }

                                    if(set == '1') {
                                        $('helpbtn-c'+comm_id).addClass('set');
                                    } else {
                                        $('helpbtn-c'+comm_id).removeClass('set');
                                    }
                                }
                            }
                          });
    req.send("cid="+courseid+"&id="+full_id);
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
    var oldElem = $('qmsg-q'+qid);
    subject.replaces($('subj-q'+qid));
    oldElem.dissolve().get('reveal').chain(function() {
                                               container.replaces($('qmsg-q'+qid));
                                               CKEDITOR.replace('editmsg-q'+qid, { customConfig: config });
                                               container.reveal();
                                               oldElem.destroy();
                                               new OverText($('editwhy-q'+qid));
                                           });
/*    subject.replaces($('subj-q'+qid));
    container.replaces($('qmsg-q'+qid));
    CKEDITOR.replace('editmsg-q'+qid, { customConfig: config });
    new OverText($('editwhy-q'+qid));*/
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
    req.post({cid: courseid,
              qid: qid,
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
                                show_spinner($('delbtn-q'+qid));
                            },
                            onSuccess: function(respText, respXML) {
                                hide_spinner($('delbtn-q'+qid));
                                $('delbtn-q'+qid).removeClass('working');

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
    req.send("cid="+courseid+"&qid="+qid);
}


/** Add an answer to the specified question
 *
 * @param questionid The ID of the question to add the answer to.
 */
function add_answer(questionid)
{
    if(apostlock) return false;
    apostlock = true;

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
                                     apostlock = false;
                                 }
                               });
    req.post({cid: courseid,
              id: questionid,
              message: CKEDITOR.instances['new-answer'].getData()
             });

    return false;
}


/** Attempt to delete an answer from the answer list. This askes the
 *  server to delete the specified answer and if the entry is deleted
 *  it removes it from the page.
 *
 * @param qid    The ID of the question this is an answer to.
 * @param aid  The ID of the answer to attempt to delete.
 */
function delete_answer(qid, aid)
{
    var req = new Request({ url: api_request_path("qaforum", "deletea"),
                            onRequest: function() {
                                $('delbtn-a'+aid).addClass('working');
                                show_spinner($('delbtn-a'+aid));
                            },
                            onSuccess: function(respText, respXML) {
                                hide_spinner($('delbtn-a'+aid));
                                $('delbtn-a'+aid).removeClass('working');

                                var err = respXML.getElementsByTagName("error")[0];
                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();

                                // No error, answer was deleted
                                } else {
                                    $('aid-'+aid).dissolve().get('reveal').chain(function() {
                                                                                     $('aid-'+aid).destroy();
                                                                                     var list = $('answers').getChildren();
                                                                                     $('anscount').set('html', list.length);
                                                                                 });
                                }
                            }
                          });
    req.post({ cid: courseid,
               qid: qid,
               aid: aid
             });
}


/** Convert an answer to a form suitable for editing. This replaces the answer with a ckeditor
 *  text area, and adds a 'reason' box and an 'edit' button.
 *
 * @param qid    The ID of the question this is an answer to.
 * @param aid    The ID of the answer to convert to edit mode.
 * @param config The ckeditor configuration to use.
 */
function make_answer_editable(qid, aid, config)
{
    // Fix up the click action on the edit button before doing anything else
    $('editbtn-a'+aid).removeEvent('click');
    $('editbtn-a'+aid).addClass('ctrldisabled');

    // Create the input elements needed to make the edit work
    var message = new Element('div', { 'class': 'textwrapper'
                                     }).adopt(new Element('textarea', { rows: 5,
                                                                        cols: 80,
                                                                        html: $('amsg-a'+aid).innerHTML,
                                                                        id: 'editmsg-a'+aid
                                                                      }));
    var submit = new Element('div',
                             { 'class': 'newpost formsubmit'
                             }).adopt([new Element('input', { type: 'text',
                                         size: 70,
                                         maxlength: 128,
                                         id: 'editwhy-a'+aid,
                                         title: whyfield_name,
                                         'class': 'whybox'
                                       }),
                                       new Element('img', { id: 'workspin-a'+aid,
                                                            style: 'opacity: 0',
                                                            src: spinner_url,
                                                            height: '16',
                                                            width: '16',
                                                            alt: 'working'}),
                                       new Element('input', { type: 'button',
                                                              id: 'edit-a'+aid,
                                                              name: 'edit-a'+aid,
                                                              'class': 'button blue',
                                                              onclick: 'edit_answer(\''+qid+'\', \''+aid+'\')',
                                                              value: editbtn_name })]);
    var container = new Element('div', {'class': 'editbox', style: 'display: none'}).adopt([message, submit]);


    // Attach them to the page in place of the original elements
    var oldElem = $('amsg-a'+aid);
    oldElem.dissolve().get('reveal').chain(function() {
                                               container.replaces($('amsg-a'+aid));
                                               CKEDITOR.replace('editmsg-a'+aid, { customConfig: config });
                                               container.reveal();
                                               oldElem.destroy();
                                               new OverText($('editwhy-a'+aid));
                                           });
}


/** AJAX function to take the contents of the editor fields for an answer and ask
 *  the server to update the answer. If the update succeeds, this replaces the edit
 *  fields with the returned content.
 *
 * @param qid The ID of the question containing the answer being updated.
 * @param aid The ID of the answer being edited.
 */
function edit_answer(qid, aid)
{
    if(apostlock) return false;
    apostlock = true;

    var req = new Request.HTML({ url: api_request_path("qaforum", "edita"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('workspin-a'+aid).fade('in');
                                     $('edit-a'+aid).removeEvents('click');
                                     $('edit-a'+aid).addClass('disabled');
                                 },
                                 onSuccess: function(respTree, respElems, respHTML) {
                                     var err = respHTML.match(/^<div id="apierror"/);

                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();

                                         $('workspin-a'+aid).fade('out');
                                         $('edit-a'+aid).removeClass('disabled');
                                         $('edit-a'+aid).addEvent('click', function() { edit_answer(qid, aid); });

                                     // No error, post was edited, the element provided should
                                     // be the updated <li>...
                                     } else {
                                         var tmp = new Element('div').adopt(respTree);
                                         tmp = tmp.getChildren()[0];

                                         var oldElem = $('aid-'+aid);
                                         oldElem.dissolve().get('reveal').chain(function() { CKEDITOR.instances['editmsg-a'+aid].destroy();
                                                                                             tmp.replaces(oldElem).reveal();
                                                                                             oldElem.destroy(); });

                                     }
                                     apostlock = false;
                                 }
                               });
    req.post({cid: courseid,
              qid: qid,
              aid: aid,
              reason: $('editwhy-a'+aid).get('value'),
              message: CKEDITOR.instances['editmsg-a'+aid].getData()
             });
}


/** Add an comment to the specified question or answer
 *
 * @param id The mode and ID of the question/answer to add the comment to
 */
function add_comment(id)
{
    if(cpostlock) return false;
    cpostlock = true;

    var req = new Request.HTML({ url: api_request_path("qaforum", "comment"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('spin-'+id).fade('in');
                                     $('addcomm-'+id).removeEvents('click');
                                     $('addcomm-'+id).addClass('disabled');
                                 },
                                 onSuccess: function(respTree, respElems, respHTML) {
                                     var err = respHTML.match(/^<div id="apierror"/);

                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();

                                     // No error, post was edited, the element provided should
                                     // be the new <li>...
                                     } else {

                                         var tmp = new Element('div').adopt(respTree);
                                         tmp = tmp.getChildren()[0];
                                         tmp.setStyle("display", "none");
                                         tmp.inject($('comms-'+id), 'bottom');
                                         tmp.reveal();

                                         var count = tmp.getElement('div.helpfuls');
                                         if(count) count.fade('out');
                                     }

                                     $('msg-'+id).set('value', '');
                                     $('spin-'+id).fade('out');
                                     $('addcomm-'+id).removeClass('disabled');
                                     $('addcomm-'+id).addEvent('click', function() { add_answer(questionid); });
                                     cpostlock = false;
                                 }
                               });
    req.post({cid: courseid,
              id: id,
              message: $('msg-'+id).get('value')
             });

    return false;
}


/** Attempt to delete a comment from the comment list. This askes the
 *  server to delete the specified comment and if the entry is deleted
 *  it removes it from the page.
 *
 * @param full_id A string containing the mode (qid, aid), the id of the
 *                question or answer the comment is attached to, and the
 *                id of the comment itself.
 */
function delete_comment(full_id)
{
    var comm_id = full_id.substr(full_id.lastIndexOf("-") + 1);

    var req = new Request({ url: api_request_path("qaforum", "deletec"),
                            onRequest: function() {
                                $('delbtn-c'+comm_id).addClass('working');
                                show_spinner($('delbtn-c'+comm_id));
                            },
                            onSuccess: function(respText, respXML) {
                                hide_spinner($('delbtn-c'+comm_id));
                                $('delbtn-c'+comm_id).removeClass('working');

                                var err = respXML.getElementsByTagName("error")[0];
                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();

                                // No error, comment was deleted
                                } else {
                                    $('cid-'+comm_id).nix();
                                }
                            }
                          });
    req.send("cid="+courseid+"&id="+full_id);
}



/** Allow the user to set the flag status on an entry
 *
 * @param full_id A string containing the id of the entry to flag.
 */
function flag(full_id)
{
    if(flaglock) return false;
    flaglock = true;

    var req = new Request.HTML({ url: api_request_path("qaforum", "flag"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('flagbtn-'+full_id).addClass('working');
                                     show_spinner($('flagbtn-'+full_id));
                                 },

                                 onSuccess: function(respTree, respElems, respHTML) {
                                     hide_spinner($('flagbtn-'+full_id));
                                     $('flagbtn-'+full_id).removeClass('working');

                                     var err = respHTML.match(/^<div id="apierror"/);

                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();

                                     // No error, entry was flagged, the element provided should
                                     // be the new <li>...
                                     } else {
                                         var tmp = new Element('div').adopt(respTree);
                                         tmp = tmp.getChildren()[0];

                                         var oldElem = $('flag-'+full_id);
                                         tmp.replaces(oldElem);
                                         oldElem.destroy();
                                     }
                                     flaglock = false;
                                 }
                               });
    req.send("cid="+courseid+"&id="+full_id);
}



window.addEvent('domready', function() {
    // Rating and 'best answer' controls for questions and answers.
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

    // allow the comment form to be toggled visible
    $$('div.commentform').each(
        function(element) {
            var showbar  = element.getElement('div.show');
            var formbody = element.getElement('div.body');
            formbody.dissolve({duration: 0});

            showbar.addEvent('click', function() {
                                 showbar.dissolve({duration: 500});
                                 formbody.reveal({duration: 500});
                             });
        }
    );

    // Hide zero helpful counters on comments
    $$('li.comment ul.ops div.helpfuls').each(
        function(element) {
            if(element.get('html') == '0')
                element.fade('out');
        }
    );

    // Enable comment addition
    $$('div.comment.button').each(
        function(element) {
            var fullid = element.get('id');
            var id = fullid.substr(8);

            element.addEvent('click', function() { add_comment(id); });
        }
    );
});