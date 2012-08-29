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
               secid: sectionid
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


/** Save the title set for the specified section
 *
 */
function edit_section(sectionid)
{
    var req = new Request({ url: api_request_path("materials", "editsection"),
                            method: 'post',
                            onRequest: function() {
                                $('edittitle-'+sectionid).disabled = true;
                            },
                            onSuccess: function(respText, respXML) {
                                var err = respXML.getElementsByTagName("error")[0];
                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();
                                    $('edittitle-'+sectionid).disabled = false;
                                } else {
                                    var newval = respXML.getElementsByTagName("response")[0];

                                    var title = new Element('h3', { id:  'title-'+sectionid,
                                                                    html: newval.getAttribute('title') });
                                    var input = $('edittitle-'+sectionid);
                                    title.replaces(input);
                                    input.destroy();

                                    $('editsec-'+sectionid).removeClass('ctrldisabled');
                                    $('editsec-'+sectionid).addEvent('click', function() { make_section_editable(sectionid); });
                                }
                            }
                          });

    req.post({cid: courseid,
              secid: sectionid,
              title: $('edittitle-'+sectionid).value });
}


/** Cancel a previously started section edit operation.
 *
 */
function cancel_editable(sectionid)
{

    var input = $('edittitle-'+sectionid);
    var title = new Element('h3', { id:  'title-'+sectionid,
                                    html: input.get('value') });
    title.replaces(input);
    input.destroy();

    $('editsec-'+sectionid).removeClass('ctrldisabled');
    $('editsec-'+sectionid).addEvent('click', function() { make_section_editable(sectionid); });
}


/** Make a section title editable by the user.
 *
 */
function make_section_editable(sectionid)
{

    $('editsec-'+sectionid).removeEvents('click');
    $('editsec-'+sectionid).addClass('ctrldisabled');

    var title = new Element('input', { type: 'text',
                                       size: 70,
                                       maxlength: 128,
                                       value: $('title-'+sectionid).get('text'),
                                       id: 'edittitle-'+sectionid,
                                       events: {
                                           blur: function(event) { edit_section(sectionid); },
                                           keyup: function(event) { if(event.code == 13) {
                                                                        edit_section(sectionid);
                                                                    // might catch escapes on some systems...
                                                                    } else if(event.code == 27) {
                                                                        cancel_editable(sectionid);
                                                                    }
                                                                  }
                                       }
                                     });
    var oldtitle = $('title-'+sectionid);
    title.replaces(oldtitle);
    oldtitle.destroy();
    title.focus();
}


/** Toggle the 'start opened' setting for the specified section
 *
 */
function default_open(sectionid)
{
    var req = new Request({ url: api_request_path("materials", "defopen"),
                            onRequest: function() {
                                $('openbtn-'+sectionid).addClass('working');
                                show_spinner($('openbtn-'+sectionid));
                            },
                            onSuccess: function(respText, respXML) {
                                hide_spinner($('openbtn-'+sectionid));
                                $('openbtn-'+sectionid).removeClass('working');

                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();
                                } else {
                                    var res = respXML.getElementsByTagName("open")[0];
                                    var set = res.getAttribute("set");

                                    if(set) {
                                        $('openbtn-'+sectionid).addClass('set');
                                    } else {
                                        $('openbtn-'+sectionid).removeClass('set');
                                    }
                                }
                            }
                          });
    req.send("cid="+courseid+"&secid="+sectionid);
}


/** Toggle the 'visible' setting for the specified section
 *
 */
function default_visible(sectionid)
{
    var req = new Request({ url: api_request_path("materials", "defvis"),
                            onRequest: function() {
                                $('visbtn-'+sectionid).addClass('working');
                                show_spinner($('visbtn-'+sectionid));
                            },
                            onSuccess: function(respText, respXML) {
                                hide_spinner($('visbtn-'+sectionid));
                                $('visbtn-'+sectionid).removeClass('working');

                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();
                                } else {
                                    var res = respXML.getElementsByTagName("visible")[0];
                                    var set = res.getAttribute("set");

                                    if(set) {
                                        $('visbtn-'+sectionid).addClass('set');
                                        $('section-'+sectionid).removeClass('sec-hide');
                                    } else {
                                        $('visbtn-'+sectionid).removeClass('set');
                                        $('section-'+sectionid).addClass('sec-hide');
                                    }
                                }
                            }
                          });
    req.send("cid="+courseid+"&secid="+sectionid);
}


/** Show or hide the body of a section based on its opened setting
 *
 */
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


function add_material(sectionid)
{
    var req = new Request.HTML({ url: api_request_path("materials", "addmatform"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('addmat-'+sectionid).addClass('working');
                                     show_spinner($('addmat-'+sectionid));
                                 },
                                 onSuccess: function(respTree, respElems, respHTML) {
                                     hide_spinner($('addmat-'+sectionid));
                                     $('addmat-'+sectionid).removeClass('working');

                                     var err = respHTML.match(/^<div id="apierror"/);

                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();
                                     } else {
                                         var tmp = new Element('div').adopt(respTree);

                                         var title = tmp.getElement('div.title').get('text');

                                         $('poptitle').set('text', title);
                                         $('popbody').empty().grab(tmp);
                                         popbox.setButtons([{title: addbtn_name, color: 'blue', event: function() { do_add_material(sectionid) } },
                                                            {title: cancelbtn_name, color: 'blue', event: function() { popbox.close(); }}]);
                                         popbox.buttons[0].disabled = true;
                                         popbox.open();
                                     }
                                 }
                               });
    req.send("secid="+sectionid);
}


function set_newmat_body(container, bodyTree, bodyJS)
{
    container.adopt(bodyTree);

    // Now that the response html is in the dom tree, javascript accessing
    // it should work...
    if(bodyJS) eval(bodyJS);

    ckeditlist.each(function(editname) {
                        CKEDITOR.replace(editname, { customConfig: ckeditor_config });
                    });

    $('matform').reveal().get('reveal').chain(function() { popbox._position(); });
}


function clear_newmat_body(container)
{
    container.dissolve().get('reveal').chain(function() {
                                                 ckeditlist.each(function(editname) {
                                                                     CKEDITOR.instances[editname].destroy();
                                                                 });
                                                 ckeditlist.empty();
                                                 container.empty();
                                             });
}


function select_newmat_type()
{
    var sel = $('newtype').get('value');
    if(sel) {
        var req = new Request.HTML({ url: api_request_path("materials", "addform/"+sel),
                                     method: 'post',
                                     evalScripts: false,
                                     onRequest: function() {
                                         clear_newmat_body($('matform'));
                                     },
                                     onSuccess: function(respTree, respElems, respHTML, respJS) {
                                         var err = respHTML.match(/^<div id="apierror"/);

                                         if(err) {
                                             $('errboxmsg').set('html', respHTML);
                                             errbox.open();
                                         } else {
                                             set_newmat_body($('matform'), respTree, respJS);

                                             popbox.buttons[0].disabled = false;
                                         }
                                     }
                                   });
        req.send();
    } else {
        popbox.buttons[0].disabled = true;
        clear_newmat_body($('matform'));
    }
}


window.addEvent('domready', function() {
    $$('ul#sectionlist li').each(function(element) { toggle_body(element); });
});