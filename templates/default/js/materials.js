var addlock = false;

function add_section() 
{
    if(addlock) return;
    addlock = true;

    var req = new Request.HTML({ url: api_request_path("materials", "addsection"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('addsecimg').fade('in');
                                     $('addsecbtn').removeEvents('click');
                                     $('addsecbtn').addClass('disabled');
                                 },
                                 onSuccess: function(respTree, respElems, respHTML) {
                                     var err = respHTML.match(/^<div id="apierror"/);
                                     
                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();
                                     } else {
                                         var tmp = new Element('div').adopt(respTree);
                                         tmp = tmp.getChildren()[0];

                                         tmp.setStyle("display", "none");
                                         tmp.inject($('addsection'), 'before');
                                         if(listsort) listsort.addItems(tmp);
                                         tmp.reveal();
                                     }
                                     $('addsecimg').fade('out');
                                     $('addsecbtn').removeClass('disabled');
                                     $('addsecbtn').addEvent('click', function() { add_section() });
                                     addlock = false;
                                 }
                               });
    req.send();
}


function save_section_order()
{
    var idlist = listsort.serialize(0, function(element, index) { 
                                        if(element.getProperty('id')) {
                                            return element.getProperty('id').replace('item_','') + '=' + index;
                                        } else {
                                            return '';
                                        }
                                    }).join('&');

    var req = new Request({ url: api_request_path("materials", "sectionorder"),
                            onSuccess: function(respText, respXML) {
                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();
                                }
                            }
                          });
    req.send(idlist);      
}


window.addEvent('domready', function() {

    $$('ul#sectionlist li.sec-close .contents').each(
        function(element) {
            element.dissolve();
        }
    );

    $$('ul#sectionlist li').each(
        function(element) {
            var toggle = element.getElement("span.togglevis");
            if(toggle) {
                var body = element.getElement("div.contents");

                toggle.addEvent('click', function() {
                                    if(element.hasClass('sec-close')) {
                                        element.removeClass('sec-close');
                                        body.reveal();
                                    } else {
                                        element.addClass('sec-close');
                                        body.dissolve();
                                    }
                                });
            }
        }
    );
});