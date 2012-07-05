
function do_fetchmore(postid)
{
    var req = new Request.HTML({ url: "api/more/",
                                 onRequest: function() {
                                     $('fetchimg').fade('in');
                                     $('fetchbtn').fade('out');
                                 },
                                 onSuccess: function(respTree, respElems) {
                                     // Remove the old fetchmore, so that the user doesn't get confused...
                                     $('showmore').dispose();
                                     $('postlist').adopt(respTree);
                                 }
                               });
    req.send("postid="+postid);
}