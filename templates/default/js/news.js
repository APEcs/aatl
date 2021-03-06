
/** Fetch more posts from the server to show in the news list. This
 *  does a HTML request to the server requesting more posts to show
 *  in the news post list.
 *
 * @param offset The offset to the first item to fetch
 */
function do_fetchmore(offset)
{
    var req = new Request.HTML({ url: api_request_path("news", "more"),
                                 onRequest: function() {
                                     $('fetchimg').fade('in');
                                     $('fetchbtn').removeEvents('click');
                                     $('fetchbtn').addClass('disabled');
                                 },
                                 onSuccess: function(respTree, respElems) {
                                     // Remove the old fetchmore, so that the user doesn't get confused...
                                     $('showmore').dispose();
                                     $('postlist').adopt(respTree);
                                 }
                               });
    req.send("cid="+courseid+"&offset="+offset);
}


/** Attempt to delete a post from the message list. This askes the
 *  server to delete the specified news entry and if the entry is deleted
 *  it removes it from the page.
 *
 * @param postid  The ID of the post to attempt to delete.
 * @param spinner The URL of a spinner image to replace the delete icon with
 *                while the delete request is being processed.
 */
function do_deletepost(postid)
{
    var req = new Request({ url: api_request_path("news", "delete"),
                            onRequest: function() {
                                $('delbtn-'+postid).addClass('working');
                                show_spinner($('delbtn-'+postid));
                            },
                            onSuccess: function(respText, respXML) {
                                hide_spinner($('delbtn-'+postid));
                                $('delbtn-'+postid).removeClass('working');

                                var err = respXML.getElementsByTagName("error")[0];
                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();

                                // No error, post was deleted
                                } else {
                                    $('post-'+postid).dissolve();
                                }
                            }
                          });
    req.send("cid="+courseid+"&postid="+postid);
}


/** Convert a post in the post list to a form suitable for editing. This
 *  replaces the post subject with an input box, the body with a ckeditor
 *  text area, and adds an 'edit post' button.
 *
 * @param postid The ID of the post to convert to edit mode.
 */
function make_editable(postid, config)
{
    // Fix up the click action on the edit button before doing anything else
    $('editbtn-'+postid).removeEvents('click');
    $('editbtn-'+postid).addClass('ctrldisabled');

    // Create the input elements needed to make the edit work
    var subject = new Element('input', { type: 'text',
                                         size: 70,
                                         maxlength: 100,
                                         value: $('subj-'+postid).text,
                                         id: 'editsub-'+postid
                                       });
    var message = new Element('div', { 'class': 'textwrapper'
                                     }).adopt(new Element('textarea', { rows: 5,
                                                                        cols: 80,
                                                                        html: $('msg-'+postid).innerHTML,
                                                                        id: 'editmsg-'+postid
                                                                      }));
    var sticky = new Element('label', {'class': 'sticky',
                                       'for': 'editstick-'+postid,
                                      }).adopt([new Element('input', {type: 'checkbox',
                                                                      id: 'editstick-'+postid,
                                                                      name: 'editstick-'+postid,
                                                                      checked: $('post-'+postid).hasClass('sticky')}),
                                                new Element('span', {html: sticky_name})
                                               ]);

    var submit = new Element('div',
                             { 'class': 'newpost formsubmit'
                             }).adopt([sticky,
                                       new Element('img', { id: 'workspin-'+postid,
                                                            style: 'opacity: 0',
                                                            src: spinner_url,
                                                            height: '16',
                                                            width: '16',
                                                            alt: 'working'}),
                                       new Element('input', { type: 'button',
                                                              id: 'editpost-'+postid,
                                                              name: 'editpost-'+postid,
                                                              'class': 'button blue',
                                                              onclick: 'do_editable(\''+postid+'\')',
                                                              value: editbtn_name })]);

    var container = new Element('div', {'class': 'editbox'}).adopt([message, submit]);

    // Attach them to the page in place of the original elements
    subject.replaces($('subj-'+postid));
    container.replaces($('msg-'+postid));
    CKEDITOR.replace('editmsg-'+postid, { customConfig: config });
    foo = 1;
}


function do_editable(postid)
{
    var oldSticky = $('post-'+postid).hasClass('sticky');
    var newSticky = $('editstick-'+postid).checked;

    var req = new Request.HTML({ url: api_request_path("news", "edit"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('workspin-'+postid).fade('in');
                                     $('editpost-'+postid).removeEvents('click');
                                     $('editpost-'+postid).addClass('disabled');
                                 },
                                 onSuccess: function(respTree, respElems, respHTML) {
                                     var err = respHTML.match(/^<div id="apierror"/);

                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();

                                         $('workspin-'+postid).fade('out');
                                         $('editpost-'+postid).removeClass('disabled');
                                         $('editpost-'+postid).addEvent('click', function() { make_editable(postid) } );

                                     // No error, post was edited, the element provided should
                                     // be the updated <li>...
                                     } else {
                                         if(oldSticky == newSticky) {
                                             var tmp = new Element('div').adopt(respTree);
                                             tmp = tmp.getChildren()[0];

                                             var oldElem = $('post-'+postid);
                                             oldElem.dissolve().get('reveal').chain(function() { CKEDITOR.instances['editmsg-'+postid].destroy();
                                                                                                 tmp.replaces(oldElem).reveal();
                                                                                                 oldElem.destroy(); });
                                         } else {
                                             location.reload();
                                         }
                                     }
                                 }
                               });
    req.post({cid: courseid,
              postid: postid,
              subject: $('editsub-'+postid).get('value'),
              message: CKEDITOR.instances['editmsg-'+postid].getData(),
              sticky: $('editstick-'+postid).checked ? "1" : "0"
             });
}
