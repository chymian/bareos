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

# Defaults
DEFAULT_JOBDEF=DefaultJob
DEFAULT_SCHEDULE=WeeklyCycle
DEFAULT_FILESET=LinuxALL

# Tuneable varibales
BACKUP_VOL="/srv/dev-disk-by-label-backup"
BACKUP_TGT="$BACKUP_VOL/bareos"
SD_TGT="$BACKUP_TGT/storage"
BOOTSTRAP_TGT="$BACKUP_TGT/bootstrap"

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

usage() {
	echo "usage: $0: [-d <jobdef> -f <fileset>] <clientname>
Setup a Job for client with the defaults JobDef: $DEFAULT_JOB and FileSet: $DEFAULT_FILESET.
clientname can be a resolvable Hostname or an IP-Address.

   -j  Use Jobdef <name> instaed of Default JobDef
   -f  Use FileSet <name> instaed of Default FileSet
   -m  Mail the Config-Doku
   Without Parameters, all existing JobDefs and FileSets will be listed.
"
} # usage

main() {
	if [ $# = 0 ]; then
		usage
		echo "\nexisting JobDefs:  $(ls -1 $BAREOS_DIR_DIR/jobdefs/*.conf|cut -d"/" -f6|xargs)"
		echo "\nexisting FileSets: $(ls -1 $BAREOS_DIR_DIR/fileset/*.conf|cut -d"/" -f6)"
	else
		case $1 in
			-j)
				JOBSET=$2
				shift; shift
				;;
			-f)
				FILESET=$2
				shift; shift
				;;
			-m)
				MAIL_DOC=true
				shift
				;;
			*)
				CLIENT=$1
				shift
				client_job ${CLIENT} ${JOBDEF:-${DEFAULT_JOBDEF}} ${FILESET:-${DEFAULT_FILESET}}
		esac
	fi

	$MAIL_DOC && mail_doc
} #main

client_job() {
	bconsole << EOF
configure add job
  Enabled="yes" \
  Client="${1}-fd" \
  Name="backup-$CLIENT-fd" \
  JobDefs="${2}" \
  FileSet="${3}" \
  Description="Standard hourly Backup"
reload
EOF

echo "
## Client added
Hostname/IP: $1
JobDef:      $2
Fileset:     $3
"
} # client_job

mail_doc() {
	pandoc -f markdown_github  -t plain ${CONFIG_DOC} |mailx -s "Backupserver BareOS Installation Doku" -A ${CONFIG_DOC}  root
	pandoc --ascii -f markdown_github  -t html ${CONFIG_DOC} >/var/www/html/$(basename $CONFIG_DOC .md).html
} # mail_doc
