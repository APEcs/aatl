
/** Fetch more posts from the server to show in the news list. This
 *  does a HTML request to the server requesting more posts to show
 *  in the news post list.
 * 
 * @param postid The ID of the first post to show in the list. 
 */
function do_fetchmore(postid)
{
    var req = new Request.HTML({ url: api_request_path("news", "more"),
                                 onRequest: function() {
                                     $('fetchimg').fade('in');
                                     $('fetchbtn').removeEvents();
                                     $('fetchbtn').addClass('disabled');
                                 },
                                 onSuccess: function(respTree, respElems) {
                                     // Remove the old fetchmore, so that the user doesn't get confused...
                                     $('showmore').dispose();
                                     $('postlist').adopt(respTree);
                                 }
                               });
    req.send("postid="+postid);
}


/** Attempt to delete a post from the message list. This askes the 
 *  server to delete the specified news entry and if the entry is deleted
 *  it removes it from the page.
 * 
 * @param postid  The ID of the post to attempt to delete.
 * @param spinner The URL of a spinner image to replace the delete icon with
 *                while the delete request is being processed.
 */
function do_deletepost(postid, spinner)
{
    var req = new Request({ url: api_request_path("news", "delete"),
                            onRequest: function() {
                                $('delbtn-'+postid).oldsrc = $('delbtn-'+postid).getProperty('src');
                                $('delbtn-'+postid).setProperty('src', spinner);
                            },
                            onSuccess: function(respText, respXML) {
                                $('delbtn-'+postid).setProperty('src', $('delbtn-'+postid).oldsrc);
                                
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
    req.send("postid="+postid);  
}