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

# Set up the options for packages that insist on knowing things....
# This stops them bringing up interactive windows.....
echo sun-java5-jdk shared/accepted-sun-dlj-v1-1 select true | /usr/bin/debconf-set-selections
echo sun-java5-jre shared/accepted-sun-dlj-v1-1 select true | /usr/bin/debconf-set-selections
echo sun-java6-jdk shared/accepted-sun-dlj-v1-1 select true | /usr/bin/debconf-set-selections
echo sun-java6-jre shared/accepted-sun-dlj-v1-1 select true | /usr/bin/debconf-set-selections
echo samba samba/run_mode  select  daemons | /usr/bin/debconf-set-selections
echo samba-common samba-common/workgroup  string  WORKGROUP | /usr/bin/debconf-set-selections
echo samba-common    samba-common/dhcp       boolean false | /usr/bin/debconf-set-selections

echo dash dash/sh select false | debconf-set-selections

# Having answered the dash being /bin/sh question this will hopefully fix things
# without going into dialog
dpkg-reconfigure -u dash


# Trust the XC apt repo signing key
apt-key add /build/XCAptSigningKey.txt

# Get any updates ( I don't think there should be many at this point ) 
apt-get update || exit 33
echo y | apt-get --quiet -y dist-upgrade || exit 44

# Install the requirements for building XC
(echo y ; echo y ; echo y ; echo y ) | apt-get --quiet -y install xenclient-toolchain

# Create a user as bitbake doesn't like being run as root...
useradd -d /build build 
( echo password ; echo password ) | passwd build
( echo password ; echo password ) | passwd root

# psyco apparently makes the compile faster...
apt-get -y install python-psyco

# Lets have some handy tools for debug etc.
apt-get -y install emacs vim less lsof sudo
echo "build  ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# make terminal emulators a bit happier
apt-get -y install ncurses-term

# Create a directory for the build
mkdir -p /build
chown build /build

# Lets try and make wget use a proxy..
echo "http_proxy=squid.cam.xci-test.com:3128" > /build/.wgetrc
echo "ftp_proxy=squid.cam.xci-test.com:3128" >> /build/.wgetrc

