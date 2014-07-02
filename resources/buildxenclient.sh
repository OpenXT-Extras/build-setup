#!/bin/bash
#
# Copyright (c) 2011 Citrix Systems, Inc.
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

uname -a

MACHTYPE=`uname -m`
if [ ${MACHTYPE} == "x86_64" ];
then
echo "${MACHTYPE} - use linux32"
exit 666
fi


if [ ! -d /build ];
then
echo "This should be run under the chroot as the user build"
exit 1
fi

cd /build/
if [ -d build-scripts  ];
then
 ( cd build-scripts ; git pull )
else 
 git clone git://git.xci-test.com/xenclient/build-scripts.git
fi

cd /build/build-scripts/
cp "/build/build-scripts/configs/cam_oedev" .config || exit 1

{ "./do_build.sh" 2>&1 ; echo -n "$?" > out; } | tee "build.log"
if [ "`cat out`" -eq 0 ];  then
        echo "Green - good build"
else
        echo "RED - bad build"
fi
