#!/bin/sh
# A simple "build" script.
cd pkg_terebinth/packages/
zip -r com_terebinth com_terebinth/
zip -r plg_content_terebinth plg_content_terebinth/
zip -r plg_system_terebinth plg_system_terebinth/
cd ../../
zip -r pkg_terebinth pkg_terebinth/packages/*.zip pkg_terebinth/*.xml
