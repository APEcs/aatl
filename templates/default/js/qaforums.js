
function rate_toggle(element) 
{
    var full_id = element.get('id');
    var core_id = full_id.substr(4);

    var req = new Request({ url: api_request_path("qaforums", "rateup"),
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
                                        
                                }
                            }
                          });
    req.send("id="+core_id);  
}


function setup_ratings() {
    
    $$('div.qblock div.stats div.rating').each(
        function(element) {
            
        }
    );

}