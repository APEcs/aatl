
function do_fetchmore(postid)
{
    var reqpath = window.location.pathname;

    // Ensure it has a trailing slash
    if(reqpath.charAt(reqpath.length - 1) != '/') reqpath += '/';

    // Does the current page end in news/? If not, add it
    if(!reqpath.test('news\/$')) reqpath += "news/";
    
    reqpath += "api/more/";

    var req = new Request.HTML({ url: reqpath,
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