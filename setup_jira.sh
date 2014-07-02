#!/bin/bash
#
# Copyright (c) 2012 Citrix Systems, Inc.
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

#####
# Script to set up Jira, run from a recovery image (e.g. buildmachine).
# Assumes system with two equal disks; configures it into md RAID1, sets up
# a Debian filesystem (squeeze amd64), downloads, and installs Jira.

set -e

###
# Configuration

: ${karch:=amd64}   ## or 686
: ${arch:=amd64}    ## or i386
: ${jiraurl:=http://www.atlassian.com/software/jira/downloads/binary/atlassian-jira-4.4.3-x64.bin}
: ${h:=bird.cam.xci-test.com}
: ${ip:=}
: ${jvm_min_memory:=1024m}
: ${jvm_max_memory:=6144m}

if [ -z "$ip" ] || ! host $h &>/dev/null; then
    echo >&2 "Hostname $h could not be resolved - please check."
fi

###
# Create partitions on disks:
for d in /dev/sd{a,b} ; do 
    # p1 128M boot partition (Linux)
    # p2 Rest of disk LVM
    echo 'o
n
p
1

+128M
n
p
2


a
1
t
2
8e
w
' | fdisk $d
done

# wait for udev to figure out what we just did
[ ! -x /sbin/udevadm ] || /sbin/udevadm settle

###
# Set up md RAID1 to mirror sda1/sdb1 and sda2/sdb2:

echo y | mdadm --create /dev/md0 -n 2 -e 0.90 -l 1 /dev/sd{a,b}1
echo y | mdadm --create /dev/md1 -n 2 -e 0.90 -l 1 /dev/sd{a,b}2

###
# Put LVM onto md1, make root & boot filesystems

pvcreate -ff -y /dev/md1
vgcreate vg0 /dev/md1
lvcreate -n lv_root -L 16G /dev/vg0
lvcreate -n lv_var -L 16G /dev/vg0
lvcreate -n lv_swap -L 8G /dev/vg0
mkfs.ext3 -L bootfs /dev/md0
mkfs.ext3 /dev/vg0/lv_var
mkfs.ext3 /dev/vg0/lv_root
mkswap /dev/vg0/lv_swap

###
# Prepare, install Debian Squeeze:

mnt=$(mktemp -dt)
mount /dev/vg0/lv_root $mnt
mkdir $mnt/var
mount /dev/vg0/lv_var $mnt/var
mkdir $mnt/boot
mount /dev/md0 $mnt/boot
debootstrap --arch $arch --components=main,non-free \
        --include linux-image-2.6-$karch,grub,initramfs-tools,mdadm,lvm2,busybox,firmware-bnx2,openssh-server,ca-certificates,zabbix-agent,xauth,lighttpd,nfs-common,locales,rsync \
        squeeze $mnt http://debian.cam.xci-test.com/debian

###
# Get a bootloader installed, the system set up and ready to boot

sed -i 's,^GRUB_CMDLINE_LINUX_DEFAULT=.*$,GRUB_CMDLINE_LINUX_DEFAULT="quiet console=ttyS0\,115200n8",g' $mnt/etc/default/grub
sed -i 's,^GRUB_CMDLINE_LINUX=.*$,GRUB_CMDLINE_LINUX="console=ttyS0\,115200n8",g' $mnt/etc/default/grub
sed -i 's,^#GRUB_TERMINAL,GRUB_TERMINAL,g' $mnt/etc/default/grub
echo "T0:23:respawn:/sbin/getty -L ttyS0 115200 vt100" >> $mnt/etc/inittab

cat <<EOF >$mnt/etc/fstab
# fs         mount   type    options     d   p
proc         /proc   proc    defaults    0   0
sys          /sys    sysfs   defaults    0   0
/dev/vg0/lv_root /       ext3    relatime,errors=remount-ro 0   1
/dev/vg0/lv_var  /var    ext3    relatime,errors=remount-ro 0   1
/dev/vg0/lv_swap none   swap    sw  0   0
LABEL=bootfs    /boot   ext3    relatime,errors=remount-ro 0   0
oven.cam.xci-test.com:/export/storage/jiraattachments   /var/atlassian/application-data/jira/data/attachments/  nfs defaults    0   0
EOF

# setup networking -- XXX shouldn't assume gateway etc.:
[ -n "$ip" ] || ip=$(host $h | cut -d' ' -f 4)
cat <<EOF >$mnt/etc/network/interfaces
auto lo eth0

iface lo inet loopback

iface eth0 inet static
    address $ip
    netmask 255.255.252.0
    gateway 10.80.251.254
EOF
echo $h > $mnt/etc/hostname

mount -t proc none $mnt/proc
mount -t sysfs none $mnt/sys
mount --bind /dev $mnt/dev

ln -s /proc/mounts $mnt/etc/mtab     # make df work

chroot $mnt grub-install /dev/sda
chroot $mnt update-grub
chroot $mnt update-initramfs -u -k all

echo 'root:password' | chroot $mnt chpasswd

# generate locales
sed -i 's,# en_GB,en_GB,' $mnt/etc/locale.gen
sed -i 's,# en_US,en_US,' $mnt/etc/locale.gen
chroot $mnt locale-gen

###
# Configure Zabbix

# TODO

###
# Download and install Jira into the target:

echo "$jiraurl" >$mnt/root/jira.url
wget -O $mnt/root/jira.bin "$jiraurl"

# Unattended mode doesn't work properly... :(
# o <enter>    -- ok to continue with installation
# 1 <enter>    -- fresh install, not upgrade
# <enter>      -- default installation path is OK (/opt/atlassian/jira)
# <enter>      -- default home directory is OK /var/atlassian/application-data)
# 1 <enter>    -- default values for HTTP ports (8080 for main server)
# y <enter>    -- run Jira as a service (i.e. create init.d stuff for it)
echo 'o
1


1
y
' | chroot $mnt bash /root/jira.bin

# the installer insists on actually starting Jira (regardless of executeLauncherAction), 
# so shut it back down cleanly:
chroot $mnt /opt/atlassian/jira/bin/stop-jira.sh

# configure JVM memory
sed -i "s,^JVM_MINIMUM_MEMORY=.*,JVM_MINIMUM_MEMORY=\"${jvm_min_memory}\"," $mnt/opt/atlassian/jira/bin/setenv.sh
sed -i "s,^JVM_MAXIMUM_MEMORY=.*,JVM_MAXIMUM_MEMORY=\"${jvm_max_memory}\"," $mnt/opt/atlassian/jira/bin/setenv.sh

# make sure attachments directory exists as we refer to it in fstab
mkdir -p $mnt/var/atlassian/application-data/jira/data/attachments

# configure link to AD

###
# Configure lighttpd as a proxy so we can run Tomcat as an unprivileged user

cat <<EOF > $mnt/etc/lighttpd/conf-available/11-proxy-to-8080.conf
server.modules   += ( "mod_proxy" )

proxy.server     = ( "" =>
                     ( 
                       ( "host" => "127.0.0.1",
                         "port" => 8080
                       )
                     )
                    )
EOF
( cd $mnt/etc/lighttpd/conf-enabled && ln -s ../conf-available/11-proxy-to-8080.conf )

rm -f $mnt/etc/mtab && touch $mnt/etc/mtab
umount $mnt/{proc,sys,dev,boot,var,}

echo "Jira configuration complete."

