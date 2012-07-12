/** Generate a request path to send AJAX requests to. This will 
 *  automatically compensate for missing url fragments if needed.
 * 
 * @param block     The system block the API is provided by.
 * @param operation The API operation to perform.
 * @return A string containing the request path to use.
 */
function api_request_path(block, operation)
{
    var reqpath = window.location.pathname;

    // Ensure the request path has a trailing slash
    if(reqpath.charAt(reqpath.length - 1) != '/') reqpath += '/';

    // Does the current page end in news/? If not, add it
    if(!reqpath.test(block+'\/$')) reqpath += (block + "/");
    
    // Add the api call
    reqpath += "api/" + operation + "/";
    
    return reqpath;
}

