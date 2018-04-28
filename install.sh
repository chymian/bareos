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
BAREOS_USER="bareos"
BAREOS_BASE_DIR="/etc/bareos"
BAREOS_DIR_DIR="$BAREOS_BASE_DIR/bareos-dir.d"

PREREQ="pwgen uuid-runtime git make mailutils pandoc"
agi='apt-get install --yes --force-yes --allow-unauthenticated  --fix-missing --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'
agu='apt-get update'
DEBIAN_FRONTEND=noninteractive
mail=/usr/bin/mail.mailutils
HTML_TGT=/var/www/html
CFG_TAR=bareos-etc.tar.gz
ROOTFS_UUID=$(findmnt -no UUID /)
ROOTFS_OPTIONS=$(for i in $(grep $ROOTFS_UUID /etc/fstab|awk '{print $4}'|cut -d',' --output-delimiter=" " -f1,2,3,4,5,6,7,8,9,10); do echo $i; done|grep -v subvol|xargs|tr " " ",")

usage() {
# Switches not implemented yes
	echo "$0 usage [options]

Options:
  -m <email>      eMail-Addr to send installation report to
  -a <name>       WebUI Admin Name
  -w <password>   WebUI Admin Password
  -c <name>       Setup Client Job (only), no Installation of BareOS-Server
"
} # usage

main() {

	install_prereq
	install_base
	restart_daemons
	install_webui
	configure_base
	finish_docu
} # main

install_prereq() {
echo "# BareOS Backup Server

## Installationprotocol
\`\`\`
on:              $SERVER
Date:            `date`
BarOS Version:   16.2
\`\`\`

" > $CONFIG_DOC

	# add repo for webUI
	URL=http://download.bareos.org/bareos/$WEBUI_RELEASE/$WEBUI_DIST
	# add the Bareos repository
	printf "deb $URL /\n" > /etc/apt/sources.list.d/bareos.list

	# add package key
	wget -q $URL/Release.key -O- | apt-key add -

	# install Bareos packages
	$agu  >/dev/null 2>&1
	$agi $PREREQ
	# needed to send attached Files
	update-alternatives --set mailx /usr/bin/mail.mailutils

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

	# add root-subvol mount /mnt/.btrfs/root to fstab
	grep -v "/mnt/.btrfs/root" /etc/fstab > /tmp/fstab.tmp
	printf "UUID=${ROOTFS_UUID}\t/mnt/.btrfs/root\tbtrfs\t${ROOTFS_OPTIONS}\t0 1\n" >> /tmp/fstab.tmp
	mv --backup=t /tmp/fstab.tmp /etc/fstab

	# add backup-target to fstab
	grep -v "/var/lib/bareos" /etc/fstab > /tmp/fstab.tmp
	printf "$BACKUP_TGT\t\t/var/lib/bareos\t\tnone\tbind\t0 0\n" >> /tmp/fstab.tmp
	mv --backup=t /tmp/fstab.tmp /etc/fstab

	# create mountpoint
	mkdir -p /var/lib/bareos /mnt/.btrfs/root
	mount -a
	# mount the $BACKUP_TGT & rootfs-root
	[ -d /var/lib/bareos/storage ] || {
		echo "ERR: Cannot mount /var/lib/bareos. exiting…"
		exit 2
	}


echo "## Targets  
are mounted under \`/var/lib/bareos\` and available on:  
\`\`\`
Backup Volume:       $BACKUP_VOL
Backup Target:       $BACKUP_TGT
Storage Target:      $SD_TGT
Bootstrap Target:    $BOOTSTRAP_TGT
\`\`\`
" >> $CONFIG_DOC


	# update from git-repo
	cd $WORK_DIR
	git pull

} # install_prereq

install_base() {

	# Preseeding debconf for not getting asked during installation

	#echo bareos-database-common dbconfig-install       boolean	 true					| debconf-set-selections
	#echo bareos-database-common database-type          select	 pgsql					| debconf-set-selections
	#echo bareos-database-common remote/host	           select	 localhost				| debconf-set-selections

	#echo bareos-database-common pgsql/admin-user       string	 ${PGSQL_ADMIN:-postgres}		| debconf-set-selections
	#echo bareos-database-common pgsql/admin-pass       password	 ${PGSQL_ADMIN_PW:-$(pwgen -1 13)}	| debconf-set-selections
	#echo bareos-database-common password-confirm       password	 ${PGSQL_ADMIN_PW}			| debconf-set-selections

	#echo bareos-database-common pgsql/app-pass         password	 ${PGSQL_BAREOSDB_PW:-$(pwgen -1 13)}	| debconf-set-selections
	#echo bareos-database-common app-password-confirm   password	 ${PGSQL_BAREOSDB_PW}			| debconf-set-selections


	#echo bareos-database-common/db/dbname              | debconf-set-selections
	#echo bareos-database-common/db/app-user            | debconf-set-selections

	$agi postgresql
	$agi bareos bareos-database-postgresql
	chown -R $BAREOS_USER. $SD_TGT $SAMPLE_DIR

	# to use the directory-structure (>=16.2), move old-style conf-files out of the way
	cd $BAREOS_BASE_DIR
	[ -f bareos-dir.conf ] && mv bareos-dir.conf .bareos-dir.conf
	[ -f bareos-fd.conf  ] && mv bareos-fd.conf .bareos-fd.conf
	[ -f bareos-sd.conf  ] && mv bareos-sd.conf .bareos-sd.conf
	[ -f bareos-dir.conf.dist ] && mv bareos-dir.conf.dist .bareos-dir.conf.dist
	[ -f bareos-fd.conf.dist  ] && mv bareos-fd.conf.dist .bareos-fd.conf.dist
	[ -f bareos-sd.conf.dist  ] && mv bareos-sd.conf.dist .bareos-sd.conf.dist
	find . -type f -exec chmod 644 {} \;

	#echo "## Database Passwords
#PostgreSQL Admin:	$PGSQL_ADMIN_PW
#BareOS DB:		$PGSQL_BAREOSDB_PW
#" >> $CONFIG_DOC


} # install_base

install_webui() {

	$agi bareos-webui apache2 libapache2-mod-php
	restart_daemons
	# adjusting Apache2 to coexists with nginx
	cd /etc/apache2
	sed -i s/80/81/g ports.conf
	sed -i s/443/8443/g ports.conf
	#which a2dissite && a2dissite  000-default
	which a2enmod  && a2enmod proxy_fcgi setenvif 2> /dev/null || true
	which a2enconf && a2enconf php7.0-fpm 2> /dev/null || true
	which a2enmod  && a2enmod rewrite setenv php7 2> /dev/null || true
	which a2enmod  && a2enmod rewrite setenv php5 2> /dev/null || true
	which a2enconf && a2enconf bareos-webui
	service  apache2 restart


	# generate a PW if empty
	WEBUI_PW=${WEBUI_PW:-$(pwgen -1 12)}

	echo "configure add console name=$WEBUI_ADM password=$WEBUI_PW profile=webui-admin"|bconsole
	reload_director

	# Setup HTAUTH for the config-Doc Website:
	echo $WEBUI_PW | htpasswd -i -c /var/www/html/.htpasswd admin

	# allow htauth
	cd /etc/apache2/
	cat << EOF | patch -bp3
--- /tmp/apache2/apache2.conf	2018-03-31 15:54:33.916158385 +0200
+++ /etc/apache2/apache2.conf	2018-03-31 16:20:46.510808974 +0200
@@ -169,7 +169,7 @@
 
 <Directory /var/www/>
 	Options Indexes FollowSymLinks
-	AllowOverride None
+	AllowOverride All
 	Require all granted
 </Directory>
 
--- /tmp/apache2/sites-available/000-default.conf	2017-09-19 20:56:09.000000000 +0200
+++ /etc/apache2/sites-available/000-default.conf	2018-03-31 16:22:49.650415936 +0200
@@ -26,6 +26,13 @@
 	# following line enables the CGI configuration for this host only
 	# after it has been globally disabled with "a2disconf".
 	#Include conf-available/serve-cgi-bin.conf
+
+	<Directory "/var/www/html">
+		AuthType Basic
+		AuthName "Restricted Content"
+		AuthUserFile /etc/apache2/.htpasswd
+		Require valid-user
+	</Directory>
 </VirtualHost>
 
 # vim: syntax=apache ts=4 sw=4 sts=4 sr noet
EOF


	cat << EOF | cat - > /var/www/html/.htaccess
AuthType Basic
AuthName "Restricted Content"
AuthUserFile /var/www/html/.htpasswd
Require valid-user
EOF

#	sed "s#</VirtualHost>#\n    <Directory \"/var/www/html\">\n\
#        AuthType Basic\n\
#        AuthName \"Restricted Content\"\n\
#        AuthUserFile /var/www/html/apache2/.htpasswd\n\
#        Require valid-user\n\
#    </Directory>\n\n\</VirtualHost>#g" /etc/apache2/sites-available/000-default.conf


	echo "## Webinterface
Link: [http://$SERVER:81/bareos-webui/](http://$SERVER:81/bareos-webui/)

\`\`\`
WebUI User:     $WEBUI_ADM
WebUI Password: $WEBUI_PW
\`\`\`
" >> $CONFIG_DOC

} # install_webui



configure_base() {
	# copy the sample-configs to $BAREOS_BASE_DIR
	cp --backup=t -a $SAMPLE_DIR/* $BAREOS_BASE_DIR

	# Changing Directory-Name from bareos to hostname
	cd $BAREOS_BASE_DIR
	for i in `grep bareos-fd  -lr * `; do sed -i s/bareos-fd/$SERVER-fd/g $i; done
	for i in `grep bareos-dir -lr * `; do sed -i s/bareos-dir/$SERVER-dir/g $i; done
	for i in `grep bareos-mon -lr * `; do sed -i s/bareos-mon/$SERVER-mon/g $i; done
	for i in `grep bareos-sd  -lr * `; do sed -i s/bareos-sd/$SERVER-sd/g $i; done

	# make sure, fileset ist set in Job "backup-$SERVER-fd"
	mv $BAREOS_DIR_DIR/job/backup-bareos-fd.conf $BAREOS_DIR_DIR/job/backup-${SERVER}-fd.conf
	if [ `grep -ci fileset $BAREOS_DIR_DIR/job/backup-${SERVER}-fd.conf` = 1 ] ; then
		sed -i "s/.ile.et.*/FileSet = LinuxHC/g" $BAREOS_DIR_DIR/job/backup-${SERVER}-fd.conf
	else
		sed -i "s/\}/  FileSet = LinuxHC\n  \}/g" $BAREOS_DIR_DIR/job/backup-${SERVER}-fd.conf
	fi

	# if running on OMV/armbian HC1, use special job for host
	if [ -d /etc/openmediavault -a -f /etc/armbian.txt ]; then
		mv $BAREOS_DIR_DIR/job/backup-${SERVER}-fd.conf   $BAREOS_DIR_DIR/job/backup-${SERVER}-fd.conf.dist
		mv $BAREOS_DIR_DIR/job/backup-OMV-fd.conf.dist $BAREOS_DIR_DIR/job/backup-OMV-fd.conf
	fi

	# make sure, client is set in job/BackupCatalog.conf
	if [ `grep -ci client $BAREOS_DIR_DIR/job/BackupCatalog.conf` = 1 ] ; then
		sed -i "s/.ient.*/lient = $SERVER-fd/g" $BAREOS_DIR_DIR/job/BackupCatalog.conf
	else
		sed -i "s/Level/Client = $SERVER-fd\n  Level/g" $BAREOS_DIR_DIR/job/BackupCatalog.conf
	fi

	# setup messaging email, needs OMV messaging set up
	MAILFROM=$(grep sender /etc/openmediavault/config.xml |cut -d">" -f2|cut -d"<" -f1)
	sed -i "s/@localhost//g" $BAREOS_DIR_DIR/messages/* $BAREOS_DIR_DIR/job/*
	sed -i "s/-f.*-s/-f $MAILFROM -s/g" $BAREOS_DIR_DIR/messages/* $BAREOS_DIR_DIR/job/*

echo "## Services Passwords  
\`\`\`" >> $CONFIG_DOC
for i in DIRECTOR CLIENT STORAGE ; do
	printf "${i}_PASSWORD:\t\t$(grep ${i}_PASSWORD $BAREOS_BASE_DIR/.rndpwd|cut -d"=" -f2)\n" >> $CONFIG_DOC
done

for i in DIRECTOR_MONITOR CLIENT_MONITOR STORAGE_MONITOR; do
	printf "${i}_PASSWORD:\t$(grep ${i}_PASSWORD $BAREOS_BASE_DIR/.rndpwd|cut -d"=" -f2)\n" >> $CONFIG_DOC

done
echo "\`\`\`  
" >> $CONFIG_DOC

echo "## End of Server-Installation

Succesfully installed:
\`\`\`
Server:     ${SERVER}
OS:         $(lsb_release -d|awk '{print $2,$3,$4,$5}')
BareOS:     $(apt-cache show policy bareos|grep Version|awk '{print $2}')
PostgreSQL: $(apt-cache show policy postgresql|grep Version|awk '{print $2}')
\`\`\`

A tarball of the configuration Directory \'$BAREOS_BASE_DIR\' is available at [http://$SERVER:81/$CFG_TAR](http://$SERVER:81/$CFG_TAR)

This Page is also availlable on: [http://$SERVER:81/$(basename $CONFIG_DOC .md).html](http://$SERVER:81/$(basename $CONFIG_DOC .md).html) with the WebUI Password, I just mailed you.

***
" >> $CONFIG_DOC
} # configure_base


restart_daemons() {
	chown -R $BAREOS_USER. $BAREOS_BASE_DIR /var/lib/bareos/
	service bareos-dir restart
	service bareos-fd restart
	service bareos-sd restart
} # restart_daemons


reload_director(){
	echo reload | bconsole
} # reload_director


finish_docu() {
	cd /etc
	tar czf $WORK_DIR/$CFG_TAR bareos
	cp $WORK_DIR/$CFG_TAR $HTML_TGT
	cp $WORK_DIR/$CFG_TAR /root
	cd $WORK_DIR
	cp $CONFIG_DOC /root
	pandoc -f markdown_github -t plain ${CONFIG_DOC} |$mail -s "Backupserver BareOS Installation Report" -A ${CONFIG_DOC} -A $WORK_DIR/$CFG_TAR root
	pandoc --ascii -f markdown_github -t html ${CONFIG_DOC} > $HTML_TGT/$(basename $CONFIG_DOC .md).html
} # finish_docu

# Main
main
restart_daemons

# vim: ts=4 sw=4 sts=4 sr noet
