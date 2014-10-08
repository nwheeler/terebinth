Terebinth
==============

This package (Joomla! 3.x Extension) seeks to support Varnish a little better when used as a reverse caching proxy server in front of Joomla!

Purpose
==============

1. Sets a cookie "loggedin" if a user is logged in. This is used in your Varnish VCL file to help determine whether or not you wish to be served (and to cache) files from/to cache.
1. Provides an interface to allow you to "add" varnish servers. Once added, you can select the varnish servers and click the "Purge" button. This will cause a BAN action to be sent to the selected Varnish servers. The VCL must be set up to support the BAN method -- this is currently the only way to "wildcard purge" cache.
1. When an article/content is updated, it attempts to figure out the path that content can be seen on. (With pretty SEO on, an example would be: /using-joomla/extensions/components/weblinks-component". It then walks to the root, and purges everything in it's path. This isn't the best way to go about it, but there's no real good way in Joomla to answer the question "what URLs can access this content I just updated?". So, this'll do. (this means the following gets purged: /, /using-joomla/, /using-joomla/extensions/, /using-joomla/extensions/components/, and /using-joomla/extensions/components/weblinks-component).

Download and assemble
==============

1. Clone the repository and initialize the submodules.

    ```sh
    git clone https://github.com/nwheeler/terebinth.git
    cd terebinth
    git submodule init
    git submodule update
    ```

1. Run build.sh to package up all the things.
1. The result will be "pkg_terebinth.zip"


Install
==============

1. Go to the Extension Manager and install the zip file.

Varnish Server Configuration
==============

The default server is a localhost varnish server on the default port.

1. Components -> Terebinth
1. Select and edit the default server as appropriate for your environment.

Uninstall
==============

1. Go to the Extension Manager -> Manage
1. Search for "Terebinth"
1. Uninstall "Terebinth", the package.

Varnish VCL Example
==============

I'll be working on creating a generic "suitable for most people" Joomla/Varnish VCL configuration file which takes advantage of the features this plugin provides.

Notes
==============

1. If you like, you can also install the "plg_user_terebinth" plugin separately (via the zip file). This allows you to get the "loggedin" cookie for use with varnish, without any of the other integration stuff. This is nicer than editing core Joomla files to get this functionality.
1. The other plugin, "plg_content_terebinth" makes no sense to install independently and probably will fail horribly without the component.
1. You can install the component, "com_terebinth" by itself. This merely gives an administrator a simple way to "purge" (BAN) varnish cache.

License
==============

1. GPL v2.0 and such. See LICENSE file.

DISCLAIMER OF WARRANTY
==============
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 

Contact
==============
If you end up using this in production, let me know! I'm curious. I'm willing to help you out with any problems you may encounter. If you wish to send me an e-mail, do so at nwheeler@devis.com.
