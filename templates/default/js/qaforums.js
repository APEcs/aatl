
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


window.addEvent('domready', function() {
    $$('div.ratectl').each(
        function(element) {
            element.addEvent('click', function() { rate_toggle(element) });
        }
    );
});