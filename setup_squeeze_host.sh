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

#####
# Script to set up a squeeze host, run from a recovery image (e.g. buildmachine).
# Assumes system with two equal disks; configures it into md RAID1, sets up
# a Debian filesystem (squeeze amd64), downloads, and installs Jira.

set -e

karch=686
arch=i386
h=testhost.cam.xci-test.com

###
# Configuration

: ${karch:=amd64}   ## or 686
: ${arch:=amd64}    ## or i386
: ${h:=none.cam.xci-test.com}
: ${ip:=}

if [ -z "$ip" ] || ! host $h &>/dev/null; then
    echo >&2 "Hostname $h could not be resolved - please check."
fi

###
# Create partitions on disks:
for d in /dev/sda ; do 
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

echo y | mdadm --create /dev/md0 -n 1 --force -e 0.90 -l 1 /dev/sda1
echo y | mdadm --create /dev/md1 -n 1 --force -e 0.90 -l 1 /dev/sda2

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
        --include linux-image-2.6-$karch,grub,initramfs-tools,mdadm,lvm2,busybox,firmware-bnx2,openssh-server,ca-certificates,zabbix-agent,xauth,lighttpd,nfs-common \
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
LABEL=bootfs    /boot   ext3    relatime,errors=remount-ro 0   0
EOF

# setup networking -- XXX shouldn't assume gateway etc.:
[ -n "$ip" ] || ip=$(host $h | cut -d' ' -f 4)
cat <<EOF >$mnt/etc/network/interfaces
auto lo eth0

iface lo inet loopback

iface eth0 inet dhcp
EOF

echo $h > $mnt/etc/hostname
echo $h | sed s/\.$//g > $mnt/etc/mailname


mount -t proc none $mnt/proc
mount -t sysfs none $mnt/sys
mount --bind /dev $mnt/dev

#ln -s /proc/mounts $mnt/etc/mtab     # make df work

chroot $mnt grub-install /dev/sda
chroot $mnt update-grub
chroot $mnt update-initramfs -u -k all
chroot $mnt apt-get update 
chroot $mnt apt-get --quiet -y install puppet

echo 'root:password' | chroot $mnt chpasswd

mkdir -p $mnt/etc/puppet/
cat <<EOP >$mnt/etc/puppet/puppet.conf
[main]
server=puppetmaster.cam.xci-test.com
runinterval=1800
logdir=/var/log/puppet
vardir=/var/lib/puppet
ssldir=/var/lib/puppet/ssl
rundir=/var/run/puppet
factpath=$vardir/lib/facter
templatedir=$confdir/templates
EOP

sed -i s/START=no/START=yes/g $mnt/etc/default/puppet

rm -f $mnt/etc/mtab && touch $mnt/etc/mtab
umount $mnt/{proc,sys,dev,boot,var,}


