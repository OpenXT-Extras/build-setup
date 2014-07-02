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

function usage() {
echo "" 
echo "Usage: $0 <Path to create chroot> <debian distribution> <apt src>"
echo "eg :-"
echo "    http_proxy=\"http://squid.cam.xci-test.com:3128\"  ./makechroot.sh /tmp/fish squeeze http://debian.cam.xci-test.com:3142/debian/"
echo ""
}

if [ "x${http_proxy}" == "x" ];
then
http_proxy="http://squid.cam.xci-test.com:3128"
echo Setting http_proxy env to $http_proxy - specify a local cache
export http_proxy
fi

NEWROOT=$1
DIST=$2
APTSRC=$3 

WHOAMI=`whoami`

NEWARCH="i386"

CHROOTFILESRC=`dirname $0`

if [ x${WHOAMI} != "xroot" ];
then
echo "$0 - this must be run as root"
usage
exit 1
fi

if [ x${NEWROOT} == x ];
then
echo "$0 - this must be run as root"
echo "Usage: $0 <Path to create chroot> <debian distribution> <apt src>"
exit 1
fi

if [ x${DIST} == x ];
then 
echo "$0 - specify a debian dist eg squeeze" 
usage
exit 1
fi

if [ x${APTSRC} == x ];
then
echo  "$0 - specify a debian apt src"
usage
exit 1
fi

echo "Making a new ${DIST} ${NEWARCH} chroot in ${NEWROOT}"
if [ -d ${NEWROOT} ];
then
echo ${NEWROOT} already exists
exit 1;
fi

mkdir -p ${NEWROOT}

CMD=""

if [ -x `which linux32` ];
then  
CMD="linux32 "
fi

if [ -x `which debootstrap` ];
then
linux32 debootstrap --arch ${NEWARCH} ${DIST} ${NEWROOT} ${APTSRC} || exit 23
else
echo "debootstrap not found - apt-get install debootstrap linux32"
exit 3
fi

if [ $? -eq 0 ];
then

 cp /etc/resolv.conf ${NEWROOT}/etc/resolv.conf
 if [ -e ${CHROOTFILESRC}/resources/debian-${DIST}-sources.list ];
 then
 cp ${CHROOTFILESRC}/resources/debian-${DIST}-sources.list ${NEWROOT}/etc/apt/sources.list
 else 
  echo "$DIST doesnt have a sources file prepared in ${CHROOTFILESRC}/resources/debian-${DIST}-sources.list"
  exit 2
 fi
 cp ${CHROOTFILESRC}/resources/install_packages.sh ${NEWROOT}/install_packages.sh
 mkdir -p ${NEWROOT}/build
 cp ${CHROOTFILESRC}/resources/buildxenclient.sh ${NEWROOT}/build/
 cp ${CHROOTFILESRC}/resources/XCAptSigningKey.txt ${NEWROOT}/build/

 # tune2fs dies if there isnt a /etc/mtab file - Durrr
 touch ${NEWROOT}/etc/mtab
 mkdir -p ${NEWROOT}/proc
 mkdir -p ${NEWROOT}/dev
 mkdir -p ${NEWROOT}/sys
 mkdir -p ${NEWROOT}/lib/modules

 mount -t none -o rbind /proc ${NEWROOT}/proc
 mount -t none -o rbind /dev ${NEWROOT}/dev
 mount -t none -o rbind /sys ${NEWROOT}/sys
 mount -t none -o rbind /lib/modules ${NEWROOT}/lib/modules

 linux32 chroot ${NEWROOT} /install_packages.sh

else
 echo "Something went wrong...."
 exit 2
fi

echo "Ensure all rbind mounts are removed before you delete the new chroot dir ${NEWROOT}"
echo "As otherwise you may find yourself deleting /dev /lib/modules etc"
