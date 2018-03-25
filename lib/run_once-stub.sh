#!/bin/bash
# Run once to reset services
#

export  DEBIAN_FRONTEND=noninteractive
NOT_EXECUTED=/root/.run_once_not_yet

if [ "$1" = "" ]; then
	echo "Usage $0: <hostname>"
	exit 1
else
	HOSTNAME=$1
fi


# setting hostname

echo setting hostname to $HOSTNAME
echo $HOSTNAME > /etc/hostname
/bin/hostname -F /etc/hostname

cat <<EOF > /etc/hosts
127.0.0.1       localhost
127.0.1.1       $HOSTNAME

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF


# needed programs & upgrade
echo "Installing dependencies & upgrade"
#apt_swap
\apt-get -y --force-yes install btrfs-tools e2fsprogs python ssh cloud-guest-utils apt-transport-https git apt screen tmux make htop less
\apt -y full-upgrade

# sshd-keys
echo recreating ssh-keys
service ssh stop
rm -f /etc/ssh/*key*
dpkg-reconfigure openssh-server


# dhcp-leases
echo removing dhcp-leases
dhclient -r eth0
rm -f /var/lib/dhcp/*

# cleaning udev-ruls
echo cleaning udev-rules
rm -f /etc/udev/rules.d/*

# clean apt
echo cleaning apt
apt-get clean
rm -f /var/lib/apt/lists/*

# grow partition root, assuming it's the last partition
echo "growing Root-Partition if it's the last partition"
FS=$(findmnt -n -v -o FSTYPE /)		# i.e. ext2/3/4 |btrfs
rootpart=$(findmnt -n -v -o SOURCE /)	# i.e. /dev/mmcblk0p1
rootdevice=$(lsblk -n -o PKNAME $rootpart) # i.e. mmcblk0
rootdevicepath="/dev/$rootdevice"	# i.e. /dev/mmcblk0
# get the root-partition number
partition=${rootpart: -1:1}

growpart -u force $rootdevicepath $partition

case $FS in
    ext2,ext3,ext4)
	resize2fs $PART
	;;
    btrfs)
	btrfs filesystem resize max /
	;;
esac

rm $NOT_EXECUTED
reboot
exit 0
