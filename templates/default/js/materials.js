var addlock = false;
var dellock = false;

/** Add a new materials section to the current course. This asks the server to
 *  create a new section in the current course, and adds the resulting section
 *  to the end of the section list if successful.
 */
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
                                         toggle_body(tmp);
                                         
                                         
                                         tmp.reveal();
                                     }
                                     $('addsecimg').fade('out');
                                     $('addsecbtn').removeClass('disabled');
                                     $('addsecbtn').addEvent('click', function() { add_section(); });
                                     addlock = false;
                                 }
                               });
    req.send();
}


/** Delete a section from the page. This will ask the server to remove a section from the
 *  materials page, and if it succeeds the section is deleted from the page the user sees.
 */
function delete_section(sectionid)
{
    var req = new Request({ url: api_request_path("materials", "delsection"),
                            method: 'post',
                            onRequest: function() {
                                $('delsec-'+sectionid).addClass('working');
                                show_spinner($('delsec-'+sectionid));
                            },
                            onSuccess: function(respText, respXML) {
                                hide_spinner($('delsec-'+sectionid));
                                $('delsec-'+sectionid).removeClass('working');
                                
                                var err = respXML.getElementsByTagName("error")[0];
                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();

                                // No error, answer was deleted
                                } else {
                                    if(listsort) listsort.removeItems($('section-'+sectionid));

                                    $('section-'+sectionid).nix();
                                }
                            }
                          });
    req.post({ cid: courseid,
               sid: sectionid
             });  
}


/** Save the ordering of the sections in the materials page. This is called when the
 *  user finishes dragging sections to automatically save the current order.
 */
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
    req.send("cid="+courseid+"&"+idlist);      
}

function toggle_body(element) {
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

        if(element.hasClass('sec-close')) {
            body.dissolve();
        }
    }
}

window.addEvent('domready', function() {
    $$('ul#sectionlist li').each(function(element) { toggle_body(element); });
});