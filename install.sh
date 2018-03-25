#!/bin/bash
# # This installes and customizes the BareOS Directory-, Storage- and Filedaemon
# the webUI with Apache2 on port 81 to coexist with an OpenMediaVault Installation on stretch
# PostgreSQL is used, as recommended by BareOS
#
# except webUI, which is taken from bareos-repros, it's all from debian-repos
# since BareOS-Repos don't have arm(hf)-binaries
#
# MIT licence
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
WEBUI_RELEASE="release/16.2"
WEBUI_ADM="admin"
# set a password, or it will be generated later
WEBUI_PW=""

# Preseeding Postgresql Passwords
# defaults to "postgres"
PGSQL_ADMIN=""
# if left blank, will be genareted
PGSQL_ADMIN_PW=""

# defaults to "bareos@localhost"
PGSQL_BAREOSDB_USER=""
# defaults to "bareos"
PGSQL_BAREOSDB_NAME=""
# if left blank, will be genareted
PGSQL_BAREOSDB_PW=""



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

	# add repo for webUI
	URL=http://download.bareos.org/bareos/$WEBUI_RELEASE/$WEBUI_DIST
	# add the Bareos repository
	printf "deb $URL /\n" > /etc/apt/sources.list.d/bareos.list

	# add package key
	wget -q $URL/Release.key -O- | apt-key add -

	# install Bareos packages
	$agu  >/dev/null 2>&1
	$agi $PREREQ

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
	cd $WORK_DIR
	git pull

} # install_prereq

install_base() {

	# Preseeding debconf for not getting asked during installation
	echo bareos-database-common/database-type         pgsql                                    | debconf-set-selections
	echo bareos-database-common/remote/host	          localhost                                | debconf-set-selections

	echo bareos-database-common/pgsql/admin-user      ${PGSQL_ADMIN:-postgres}                 | debconf-set-selections
	echo bareos-database-common/pgsql/admin-pass      ${PGSQL_ADMIN_PW:-$(pwgen -1 13)}        | debconf-set-selections
	echo bareos-database-common/password-confirm      ${PGSQL_ADMIN_PW}                        | debconf-set-selections

	echo bareos-database-common/db/app-user           ${PGSQL_BAREOSDB_USER:-bareos@localhost} | debconf-set-selections
	echo bareos-database-common/db/dbname             ${PGSQL_BAREOSDB_NAME:-bareos}           | debconf-set-selections
	echo bareos-database-common/pgsql/app-pass        ${PGSQL_BAREOSDB_PW:-$(pwgen -1 13)}     | debconf-set-selections
	echo bareos-database-common/app-password-confirm  ${PGSQL_BAREOSDB_PW}                     | debconf-set-selections



	$agi postgresql
	$agi bareos bareos-database-postgresql
	chown -R $BAROS_USER. $SD_TGT $SAMPLE_DIR

	# to use the directory-structure (>=16.2), move old-style conf-files out of the way
	cd $BAROS_BASE_DIR
	[ -f bareos-dir.conf ] && mv bareos-dir.conf .bareos-dir.conf
	[ -f bareos-fd.conf  ] && mv bareos-fd.conf .bareos-fd.conf
	[ -f bareos-sd.conf  ] && mv bareos-sd.conf .bareos-sd.conf
	[ -f bareos-dir.conf.dist ] && mv bareos-dir.conf.dist .bareos-dir.conf.dist
	[ -f bareos-fd.conf.dist  ] && mv bareos-fd.conf.dist .bareos-fd.conf.dist
	[ -f bareos-sd.conf.dist  ] && mv bareos-sd.conf.dist .bareos-sd.conf.dist
	find . -type f -exec chmod 644 {} \;

	echo "## Database Passwords
PostgreSQL Admin:	$PGSQL_ADMIN_PW
BareOS DB:		$PGSQL_BAREOSDB_PW
" >> $CONFIG_DOC


} # install_base

install_webui() {

	$agi bareos-webui apache2 libapache2-mod-php
	restart_daemons
	# adjusting Apache2 to coexists with nginx
	cd /etc/apache2
	sed -i s/80/81/g ports.conf
	sed -i s/443/8443/g ports.conf
	a2dissite 000-default
	a2enconf bareos-webui
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

	# make sure, client is set in job/BackupCatalog.conf
	if [ `grep -ci client $BAREOSDIR_DIR/job/BackupCatalog.conf` = 1 ] ; then
		sed -i "s/.ient.*/lient = $SERVER-fd/g" $BAREOSDIR_DIR/job/BackupCatalog.conf
	else
		sed -i "s/Level/Client = $SERVER-fd\n  Level/g" $BAREOSDIR_DIR/job/BackupCatalog.conf
	fi
	# make sure, fileset ist set in Job "backup-$SERVER-fd" 
	mv $BAREOSDIR_DIR/job/backup-bareos-fd.conf $BAREOSDIR_DIR/job/backup-${SERVER}-fd.conf
	if [ `grep -ci fileset $BAREOSDIR_DIR/job/backup-${SERVER}-fd.conf` = 1 ] ; then
		sed -i "s/.ile.et.*/FileSet = LinuxHC/g" $BAREOSDIR_DIR/job/backup-${SERVER}-fd.conf
	else
		sed -i "s/\}/  FileSet = LinuxHC\n  \}/g" $BAREOSDIR_DIR/job/backup-${SERVER}-fd.conf
	fi

} # configure_base

#conf_fileset() {
	# using configured basic filesets from GIT
#} # conf_fileset






restart_daemons() {
	chown -R $BAROS_USER. $BAROS_BASE_DIR
	service bareos-dir restart
	service bareos-fd restart
	service bareos-sd restart
} #restart_daemons

reload_director(){
	echo reload | bconsole
} #reload_director

# Main
main

