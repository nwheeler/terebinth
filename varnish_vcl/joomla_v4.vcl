vcl 4.0;

import header;
import std;
import directors;

// (http) origin. This is pointing to the VirtualHost running on port 8888.
// It sets up a probe for this backend, allowing us to serve stale cache if the
// backend becomes unresponsive. Be sure to have the correct .host_header.
backend origin {
    .host   =   "127.0.0.1";
    .host_header   = "www.terebinth.info";
    .port   =   "8888";
    .first_byte_timeout = 120s;
    .probe  = {
        .url        =   "/";
        .timeout    =   30 s;
        .interval   =   2m;
        .window     =   5;
        .threshold  =   3;
    }
}

sub vcl_init {
  new b = directors.round_robin();
  b.add_backend(origin);
}

// This ACL control permissions for BAN and PURGE operations.
acl purge {
    "127.0.0.1";
}

// This method sets up what is hashed to identify a unique object. It is made out of
// the request url, the host or server ip, and if it is not static, the x-forwarded-proto
// header. As well, if the user is logged in, it hashes their cookie.
sub vcl_hash {
    hash_data(req.url);
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }
    // If it is not a static resource, include X-Forwarded-Proto in the hash (if it exists).
    // This makes dynamic content unique for ssl vs non-ssl
    if (!(req.url ~ "^[^?]*\.(bmp|bz2|css|doc|eot|flv|gif|gz|ico|jpeg|jpg|js|less|mp[34]|pdf|png|rar|rtf|swf|tar|tgz|txt|wav|woff|xml|zip)(\?.*)?$"))
    {
      if (req.http.X-Forwarded-Proto)
      {
        hash_data(req.http.X-Forwarded-Proto);
      }
    }
    // Always hash the cookies that make it this far.
    hash_data(req.http.cookie);
    return (lookup);
}

// This is the "request receive" method. This method is pretty magical. This is run 
// when the request comes into Varnish from the internet/clouds/what have you. The goal 
// of this method is determining what to do with the request...either lookup from cache,
// or pass directly to backend. Do not collect $200.

sub vcl_recv {

    set req.backend_hint = b.backend();

    // set and/or append X-Forwarded-For header.
    if (req.restarts == 0) {
        if (req.http.X-Forwarded-For) {
            set req.http.X-Forwarded-For =
            req.http.X-Forwarded-For + ", " + client.ip;
        } else {
            set req.http.X-Forwarded-For = client.ip;
        }
    }

    // Terebinth PURGE request handling
    if (req.method == "PURGE")
    {
        if (!client.ip ~ purge) {
            return (synth(405, "Not allowed."));
        }
        // Okay, this used to be PURGE, but ban works better. Still, it is an HTTP PURGE request ;).
        // The Terebinth content plugin makes use of this.
        ban("req.url == "+req.url);
        return (synth(200, "Purged "+req.url+" from cache."));
    }
    // Terebinth BAN request handling
    if (req.method == "BAN")
    {
        if (!client.ip ~ purge)
        {
            return (synth(405, "Not allowed."));
        }
        // This bans all the cache if req.url is "/". Terebinth (admin view) makes use of this.
        ban("req.url ~ "+req.url);
        return (synth(200,"Banned things like "+req.url+" from cache."));
    }

    // Only deal with "normal" types
    if (req.method != "GET" &&
            req.method != "HEAD" &&
            req.method != "PUT" &&
            req.method != "POST" &&
            req.method != "TRACE" &&
            req.method != "OPTIONS" &&
            req.method != "PATCH" &&
            req.method != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }

    if (req.method != "GET" && req.method != "HEAD") {
        // We only deal with GET and HEAD by default
        return (pass);
    }

    // Some generic URL manipulation
    // First remove the Google Analytics added parameters, useless for our backend
    if (req.url ~ "(\?|&)(utm_source|utm_medium|utm_campaign|gclid|cx|ie|cof|siteurl)=") {
        set req.url = regsuball(req.url, "&(utm_source|utm_medium|utm_campaign|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "");
        set req.url = regsuball(req.url, "\?(utm_source|utm_medium|utm_campaign|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "?");
        set req.url = regsub(req.url, "\?&", "?");
        set req.url = regsub(req.url, "\?$", "");
    }

    // Strip hash, server doesn't need it.
    if (req.url ~ "\#") {
        set req.url = regsub(req.url, "\#.*$", "");
    }

    // Strip a trailing ? if it exists
    if (req.url ~ "\?$") {
        set req.url = regsub(req.url, "\?$", "");
    }


    // handle some encoding types. Found this snippet on the interwebs. Thanks interwebs.
    if (req.http.Accept-Encoding)
    {
        if (req.url ~ "\.(jpg|jpeg|png|gif|gz|tgz|bz2|tbz|mp3|ogg|swf)$")
        {
            # No point in compressing these compressed items.
            unset req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            // unknown, so...
            unset req.http.Accept-Encoding;
        }
    }

    // See: http://mattiasgeniar.be/2012/11/28/stop-caching-static-files/
    if (req.url ~ "^[^?]*\.(bmp|bz2|css|doc|eot|flv|gif|gz|ico|jpeg|jpg|js|less|mp[34]|pdf|png|rar|rtf|swf|tar|tgz|txt|wav|woff|xml|zip)(\?.*)?$")
    {
        unset req.http.cookie;
        return (hash);
    }

    // If it is a POST request, or part of component/banners, pass to backend.
    if(req.url ~ "^/component/banners" || req.method == "POST")
    {
        return (pass);
    }

    // If your login page is not at "/login", change the below line. This statement is primarily so a user will get a unique
    // session cookie if they visit the administrator section, or the login section. You can't log into Joomla without having 
    // a valid session cookie to begin with.
    if (req.url ~ "^/login" || req.url ~ "^/administrator")
    {
        return (pass);
    }

    // Cookie processing. Here, we strip out useless cookies.
    // Remove the "has_js" cookie
    set req.http.Cookie = regsuball(req.http.Cookie, "has_js=[^;]+(; )?", "");

    // Remove any Google Analytics based cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__utm.=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "_ga=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmctr=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmcmd.=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmccn.=[^;]+(; )?", "");

    // Remove the Quant Capital cookies (added by some plugin, all __qca)
    set req.http.Cookie = regsuball(req.http.Cookie, "__qc.=[^;]+(; )?", "");

    // Remove the AddThis cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__atuvc=[^;]+(; )?", "");

    // Remove a ";" prefix in the cookie if present
    set req.http.Cookie = regsuball(req.http.Cookie, "^;\s*", "");

    // Are there cookies left with only spaces or that are empty?
    if (req.http.cookie ~ "^\s*$") {
        unset req.http.cookie;
    }

    // If you're not logged in, throw away the session cookie.
    if (!(req.http.cookie ~ "loggedin"))
    {
        // strip joomla's md5=md5 session cookie.
        set req.http.Cookie = regsub(req.http.Cookie, "[0-9a-f]{32}=[0-9a-f]{32}", "");
    }

    // End cookie processing.

    // set how long varnish will cache content depending on healthiness of backend. see .probe
    //if (std.healthy(req.backend_hint))
    //{
    //    set req.grace = 5m;
    //} else {
    //    set req.grace = 1h;
    //}

    // we've gotten this far! woohoo! lookup from cache!
    return (hash);
}

sub vcl_pipe {
    // Note that only the first request to the backend will have
    // X-Forwarded-For set. If you use X-Forwarded-For and want to
    // have it set for all requests, make sure to have:
    // set bereq.http.connection = "close";
    // here. It is not set by default as it might break some broken web
    // applications, like IIS with NTLM authentication.

    //set bereq.http.Connection = "Close";
    return (pipe);
}


// This is the "content fetch" method. This method is pretty magical, too! This is run 
// when the response comes into Varnish from Joomla!. The goal 
// of this method is determining what to do with the response...either cache it,
// or pass directly to user. We also can manipulate some HTTP headers to make client-side
// caching more effective.
sub vcl_backend_response {

    // If it is a POST, hit_for_pass.
    if (bereq.method == "POST")
    {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    // If backend says don't cache, don't cache, man. Respect.
    if ( beresp.http.Cache-Control ~ "private")
    {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    // If it is an /administrator url, don't cache it.
    if ( bereq.url ~ "^/administrator" )
    {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    // Don't cache the login page, 'cause we always want to send the (new) proper session cookie when a user wants to login.
    // A user must have a valid session cookie before authenticating, so when they receive the login page, they should also 
    // receive the set-cookie directive with their (valid) session id.
    if ( bereq.url ~ "^/login" )
    {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    // only cache responses that are HTTP 200 or 404s
    // Pass on caching objects whose response is not 200 and not 404.
    if ( beresp.status != 200 && beresp.status != 404 )
    {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    // We'll only unset Set-Cookie if it is just trying to set the Joomla session cookie. Otherwise, it is probably some
    // extension trying to set a cookie. We'll allow that. It's important to point out that logging in and logging off activities
    // likely will only work from the "/login" page.

    // required: https://github.com/varnish/libvmod-header
    //unset beresp.http.Set-Cookie;
    //This specifically removes the Joomla session cookie. You only get that cookie from /login (taken care of above).
    header.remove(beresp.http.Set-Cookie, "[0-9a-f]{32}=");

    // Allow items to be stale if required.
    set beresp.grace = 1h;

    // serve pages from the cache should we get an error, recheck in one minute
    // Basically, if the backend is throwing 500 class errors, serve from cache until we run out of time.
    if (beresp.status >= 500 && beresp.status <= 599)
    {
        set beresp.grace = 60s;
        return (retry);
    }

    // Sometimes, a 301 or 302 redirect formed via Apache's mod_rewrite can mess with the HTTP port that is being passed along.
    // This often happens with simple rewrite rules in a scenario where Varnish runs on :80 and Apache on :8080 on the same box.
    // A redirect can then often redirect the end-user to a URL on :8080, where it should be :80.
    // This may need finetuning on your setup.
    //
    // To prevent accidental replace, we only filter the 301/302 redirects for now.
    if (beresp.status == 301 || beresp.status == 302)
    {
        set beresp.http.Location = regsub(beresp.http.Location, ":[0-9]+", "");
    }

    // unset the etag header.
    unset beresp.http.etag;

    // Fix Joomla! default no-cache header, thus enabling browser-based cachings.
    // We only want to tell the browser to cache static resources, so...
    // Note: feel free to set Cache-Control for static resources in Apache. If you do so, those values will be used instead of this.
    if (bereq.url ~ "^[^?]*\.(bmp|bz2|css|doc|eot|flv|gif|gz|ico|jpeg|jpg|js|less|mp[34]|pdf|png|rar|rtf|swf|tar|tgz|txt|wav|woff|xml|zip)(\?.*)?$")
    {
        if ( beresp.http.Cache-Control == "no-cache" || beresp.http.Cache-Control == "" || !beresp.http.Cache-Control)
        {
            set beresp.http.Cache-Control = "max-age=3600, public";
        }
    }

    // cache content for 1 hour. Feel free to change this number for however long you wish Varnish to cache content for.
    // Logged in users only get cached for 2 minutes.
    if (bereq.http.cookie ~ "loggedin" )
    {
        set beresp.ttl = 2m;
    } else {
        set beresp.ttl = 60m;
    }

    // Deliver us from cache.
    return (deliver);
}


// Finally, the deliver function. I am using this just to manipulate some headers.
// For debugging, comment these "unset"s out. Otherwise, I see no reason to let them remain.
// I tend to keep X-Cache so I can easily tell if an object is being served from cache or not.

sub vcl_deliver {
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
    unset resp.http.Via;
    unset resp.http.X-Varnish;
    unset resp.http.X-Powered-By;
    unset resp.http.Server;
    unset resp.http.Pragma;
    unset resp.http.X-Content-Encoded-By;
}
