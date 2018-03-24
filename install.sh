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
BACKUP_TGT="$BACKUP_VOL/bareos"
SD_TGT="$BACKUP_TGT/storage"
BOOTSTRAP_TGT="$BACKUP_TGT/bootstrap"

# Stretch (9.0) uses 16.2
# BareOS-Repo holds 16.2 for Jessie (8.0)
# we only install the webui from there, arch: all
WEBUI_DIST="Debian_8.0"
WEBUI_RELEASE="release/16.2/"
WEBUI_ADM="admin"
# set a password, or it will generatet later
WEBUI_PW=""

# runtime vars
WORK_DIR=$(pwd)
SAMPLE_DIR="$WORK_DIR/sample-conf"
CONFIG_DOC="$WORK_DIR/BareOs-docu.md"
SERVER=`hostname`

# git stuff
GIT_REPO_NAME="bareos"
GIT_REPO="https://github.com/chymian/$GIT_REPO_NAME"

# miscellanious
BAROS_USER="bareos"
BAROS_BASE_DIR="/etc/bareos"
BAREOSDIR_DIR="$BAROS_BASE_DIR/bareos-dir.d"

PREREQ="pwgen uuid-runtime git make"
agi='apt-get install --yes --force-yes --allow-unauthenticated  --fix-missing --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'
agu='apt-get update'
DEBIAN_FRONTEND=noninteractive

main() {
	install_prereq
	install_base
	restart_daemons
	install_webui
	configure_base
} # main

install_prereq() {
echo "#####################################################################################

# Starting Installation
Datum:	`date`
" >> $CONFIG_DOC

	$agu  >/dev/null 2>&1
	$agi $PREREQ  >/dev/null 2>&1

	# check for backupTarget
	[ -w $BACKUP_VOL ] || {
		echo "ERR: BackupVolume $BACKUP_VOL does not exist, or is not writable. exiting"
		exit 1
	}

	# Create Subvolumes
	btrfs quota enable $BACKUP_VOL
	[ -d $BACKUP_TGT ] || btrfs sub cr $BACKUP_TGT
	btrfs quota enable  $BACKUP_TGT
	[ -d $SD_TGT ] || btrfs sub cr $SD_TGT
	btrfs quota enable $SD_TGT
	[ -d $BOOTSTRAP_TGT ] || btrfs sub cr $BOOTSTRAP_TGT
	btrfs quota enable $BOOTSTRAP_TGT

	# add to fstab
	grep -v "/var/lib/bareos" /etc/fstab > /tmp/fstab.tmp
	printf "$BACKUP_TGT\t\t\t/var/lib/bareos\t\tnone\tbind\t0 0\n" >> /tmp/fstab.tmp
	mv --backup=t /tmp/fstab.tmp /etc/fstab

	# create mountpoint
	mkdir -p /var/lib/bareos
	# mount the $BACKUP_TGT
	mount /var/lib/bareos || {
		echo "ERR: Cannot mount $BACKUP_TGT on /var/lib/bareos. exiting"
		exit 2
	}


echo "## Targets are mounted under \`\`\`/var/lib/bareos\`\`\` and available on:
Backup Volume:		$BACKUP_VOL
Backup Target:		$BACKUP_TGT
Storage Target:		$SD_TGT
Bootstrap Target:	$BOOTSTRAP_TGT
" >> $CONFIG_DOC


	# update git-repo with my sample-configs
	$WORK_DIR
	git pull

} # install_prereq

install_base() {
	$agi postgresql >/dev/null 2>&1
	$agi bareos bareos-database-postgresql >/dev/null 2>&1
	chown -R $BAROS_USER. $SD_TGT $SAMPLE_DIR

	# to use the directory-structure (>=16.2), move old-style conf-files out of the way
	cd $BAROS_BASE_DIR
	mv bareos-dir.conf .bareos-dir.conf
	mv bareos-fd.conf .bareos-fd.conf
	mv bareos-sd.conf .bareos-sd.conf
	mv bareos-dir.conf.dist .bareos-dir.conf.dist
	mv bareos-fd.conf.dist .bareos-fd.conf.dist
	mv bareos-sd.conf.dist .bareos-sd.conf.dist
	find -type f -exec chmod 644 {} \;

} # install_base

install_webui() {
	URL=http://download.bareos.org/bareos/$WEBUI_RELEASE/$WEBUI_DIST
	# add the Bareos repository
	printf "deb $URL /\n" > /etc/apt/sources.list.d/bareos.list

	# add package key
	wget -q $URL/Release.key -O- | apt-key add - >/dev/null 2>&1'

	# install Bareos packages
	agi bareos-webui >/dev/null 2>&1'

	# adjusting Apache2 to coexists with nginx
	sed -i s/80/81/g ports.conf
	sed -i s/443/8443/g ports.conf
	a2dissite 000-default
	service  apache2 restart

	# generate a PW if empty
	WEBUI_PW=${WEBUI_PW:-$(pwgen -1 12)}

	echo "configure add console name=$WEBUI_ADM password=$WEBUI_PW profile=webui-admin"|bconsole
	reload_director

	echo "
## Webinterface
Link: [http://$SERVER:81/bareos-webui/](http://$SERVER:81/bareos-webui/)

WebUI User:     $WEBUI_ADM
WebUI Password: $WEBUI_PW
	" >> $CONFIG_DOC
} # install_webui



configure_base() {
	# Changing Directory-Name from bareos to hostname
	cd /etc/bareos
	for i in `grep bareos-fd -lr * `; do sed -i s/bareos-fd/$SERVER-fd/g $i; done
	for i in `grep bareos-dir -lr * `; do sed -i s/bareos-dir/$SERVER-dir/g $i; done
	for i in `grep bareos-mon -lr * `; do sed -i s/bareos-mon/$SERVER-mon/g $i; done
	for i in `grep bareos-sd -lr * `; do sed -i s/bareos-sd/$SERVER-sd/g $i; done

	# copy the sample-configs to $BAROS_BASE_DIR
	cp --backup=t -a $SAMPLE_DIR/* $BAROS_BASE_DIR

	#sed -i "s/Address = .*/Address = $SERVER/g" $BAROS_BASE_DIR/bareos-dir.d/storage/File.conf
} # configure_base

#conf_fileset() {
	# Using configured basic Filesets from GIT
#} # conf_fileset






restart_daemons() {
	chown -R $BAROS_USER $BAROS_BASE_DIR
	service bareos-dir restart
	service bareos-fd restart
	service bareos-sd restart
} #restart_daemons

reload_director(){
	echo reload | bconsole
} #reload_director

# Main
main

