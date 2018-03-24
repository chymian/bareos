#!/bin/bash
# # This installes and customizes the BareOS Directory-, Storage- and Filedaemon
# the webUI with Apache2 on port 81 to coexist with an OpenMediaVault Installation on stretch
# PostgreSQL is used, as recommended by BareOS
#
# except webUI, which is taken from bareos-repros, it's all from debian-repos
# since BareOS-Repos don't have arm(hf)-binaries
#
# GPLv2
# 2018.03.21, dev@eb8.org
#



# Tuneable varibales
BACKUP_VOL="/srv/dev-disk-by-label-backup"
BACKUP_TGT="/srv/dev-disk-by-label-backup/bareos"
SD_TGT="$BACKUP_TGT/storage"
BOOTSTRAP_TGT="$BACKUP_TGT/bootstrap"
WORK_DIR=`pwd`
GIT_REPO="https://github.com/chymian/bareos-sample"
CONFIG_DOC="$WORK_DIR/BareOs-docu.md"
SERVER=`hostname`

# Stretch uses 16.2
# BareOS-Repo holds 16.2 for Deb 8.0
WEBUI_DIST="Debian_8.0"
WEBUI_RELEASE="release/16.2/"
wUI_ADM="admin"
WEBUI_PW=`pwgen -1 12`


# miscellanious
DEBIAN_FRONTEND=noninteractive
USER="bareos"
PREREQ="pwgen uuid-runtime git make"
BASE_DIR="/etc/bareos"
DIR_DIR="$BASE_DIR/bareos-dir.d"
agi='apt-get install --yes --force-yes --allow-unauthenticated  --fix-missing --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" '
agu="apt-get update -y"



install_prereq() {
echo "#####################################################################################

# Starting Installation
Datum:	`date`
" >> $CONFIG_DOC

	agi $PREREQ

	# check for backupTarget
	[ -w $BACKUP_VOL ] || { echo ERR: BackupVolume $BACKUP_VOL does not exist, or is not writable. exiting; exit 1 } 2>

	# Create Subvolumes
	btrfs sub cr $BACKUP_TGT
	btrfs sub cr $SD_TGT
	btrfs sub cr $BOOTSTRAP_TGT

	# add to fstab
	grep -v "/var/lib/bareos" /etc/fstab > /tmp/fstab.tmp
	printf "/dev/disk/by-label/backup\t\t\t/var/lib/bareos\t\tnone\tbind,subvol=bareos\t0 0\n" >> /tmp/fstab.tmp
	mv --backup=t /tmp/fstab.tmp /etc/fstab

	# create mountpoint
	mkdir -p /var/lib/bareos
	# mount the $BACKUP_TGT
	mount /var/lib/bareos || { echo ERR: Cannot mount $BACKUP_TGT on /var/lib/bareos. exiting; exit 2 } 2>


echo "## Targets are mounted under \`\`\`/var/lib/bareos\`\`\` and available on:
Backup Volume:		$BACKUP_VOL
Backup Target:		$BACKUP_TGT
Storage Target:		$SD_TGT
Bootstrap Target:	$BOOTSTRAP_TGT
" >> $CONFIG_DOC

	# get git-repo with my sample-configs
	cd $WORK_DIR
	[ ! -d bareos-sample ] && git clone $GIT
}

install_base() {
	agu
	agi postgresql
	agi bareos bareos-database-postgresql
	chown -R $USER. $SD_TGT $WORK_DIR/bareos-sample

	# to use the directory-structure (>=16.2), move old-style conf-files out of the way
	cd $BASE_DIR
	mv bareos-dir.conf .bareos-dir.conf
	mv bareos-fd.conf .bareos-fd.conf
	mv bareos-sd.conf .bareos-sd.conf
	mv bareos-dir.conf.dist .bareos-dir.conf.dist
	mv bareos-fd.conf.dist .bareos-fd.conf.dist
	mv bareos-sd.conf.dist .bareos-sd.conf.dist

}

install_webui() {
	URL=http://download.bareos.org/bareos/$WEBUI_RELEASE/$WEBUI_DIST
	# add the Bareos repository
	printf "deb $URL /\n" > /etc/apt/sources.list.d/bareos.list

	# add package key
	wget -q $URL/Release.key -O- | apt-key add -

	# install Bareos packages
	agu
	agi bareos-webui

	# adjusting Apache2 to coexists with nginx
	sed -i s/80/81/g ports.conf
	sed -i s/443/8443/g ports.conf
	a2dissite 000-default
	service  apache2 restart

	echo "configure add console name=$WEBUI_ADM password=$WEBUI_PW profile=webui-admin"|bconsole
	reload_director
	echo "
## Webinterface
Link: [http://$SERVER:81/bareos-webui/](http://$SERVER:81/bareos-webui/)

WebUI User:     $WEBUI_ADM
WebUI Password: $WEBUI_PW
	" >> $CONFIG_DOC
}



configure_base() {
	# Changing Directory-Name from bareos to hostname
	cd /etc/bareos
	for i in `grep bareos-fd -lr * `; do sed -i s/bareos-fd/$SERVER-fd/g $i; done
	for i in `grep bareos-dir -lr * `; do sed -i s/bareos-dir/$SERVER-dir/g $i; done
	for i in `grep bareos-mon -lr * `; do sed -i s/bareos-mon/$SERVER-mon/g $i; done
	for i in `grep bareos-sd -lr * `; do sed -i s/bareos-sd/$SERVER-sd/g $i; done

	# copy the sample-configs to $BASE_DIR
	cp --backup=t -a $WORK_DIR/bareos-sample/* $BASE_DIR

	#sed -i "s/Address = .*/Address = $SERVER/g" $BASE_DIR/bareos-dir.d/storage/File.conf
}

conf_fileset() {
	# Using configured basic Filesets from GIT
}






restart_daemons() {
	service bareos-dir restart
	service bareos-fd restart
	service bareos-sd restart
}

reload_director(){
	echo reload | bconsole
}

# Main

install_prereq
install_base
restart_daemons
install_webui
configure_base
