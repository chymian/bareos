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
DEFAULT_FILESET=LinuxAll
CLIENT_INI_CONN=no

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
BAREOS_USER="bareos"
BAREOS_BASE_DIR="/etc/bareos"
BAREOS_DIR_DIR="$BAREOS_BASE_DIR/bareos-dir.d"
BAREOS_EXPORT_DIR="$BAREOS_BASE_DIR/bareos-dir-export"

PREREQ="pwgen uuid-runtime git make"
agi='apt-get install --yes --force-yes --allow-unauthenticated  --fix-missing --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'
agu='apt-get update'
DEBIAN_FRONTEND="noninteractive"
mail="/usr/bin/mail.mailutils"
HTML_TGT="/var/www/html"
CFG_TAR="bareos-etc.tar.gz"
FINISH_DOCU="no"


usage() {
	echo "usage: $(basename $0) [-j <jobdef> -f <fileset>]  <clientname>
Setup a Job for client with the defaults JobDef: $DEFAULT_JOB and FileSet: $DEFAULT_FILESET.
clientname can be a resolvable Hostname or an IP-Address.

   -c		Use Client Initiated Connections, for \"not always on hosts\", like Laptops, VPS, etc
   -f <fileset> Use FileSet <fileset> instaed of Default FileSet
   -h           Show this message.
   -j <jobdef>  Use Jobdef <jobdef> instaed of Default JobDef
   -l           List JobDefs and FileSets
   -m           Mail the updated Config-Docu and config-tarball
   -s           Setup Client with bareos-fd & copy Director-definition to it

Docu & config-Tarball are not automatically updated.
Use \"-m\" on last client or by it's own at the end of your Setups.

"
exit 0
} # usage

list_defs() {
		echo "existing JobDefs:"
		echo "$(grep -i Name $BAREOS_DIR_DIR/jobdefs/*.conf|cut -d"=" -f2|sort -u)"
		echo
		echo "existing FileSets:"
		echo "$(grep -i Name $BAREOS_DIR_DIR/fileset/*.conf|cut -d"=" -f2|sort -u)"

} # list_defs


main() {
	i=0
	N=$#
	while [ $i -le $N ]; do
		echo "Anz: $#; i = $i; Para:" "$@"
		(( i++ ))
		case "$1" in
			'-c')
				CLIENT_INI_CONN=yes
				shift
				continue
				;;
			'-j')
				JOBDEF=$2
				#echo "Option -j, Arg: '$2'"
				shift 2
				continue
				;;
			'-f')
				FILESET=$2
				#echo "Option -f, Arg: '$2'"
				shift 2
				continue
				;;
			'-l')
				#echo "Option -l"
				list_defs
				exit 
				;;
			'-m')
				FINISH_DOCU=yes
				#echo "Option -m"
				shift
				break
				;;
			'-h')
				#echo "Option -h"
				usage
				exit 1
				;;
			'-s')
				#echo "Option -s"
				CLIENT_SETUP=yes
				shift
				break
				;;
			'--')
				shift
				break
				;;
#			*)
#				CLIENT=$1
#				#echo "Option -c , Arg: '$1', Clientname: $CLIENT"
#				#echo "calling client_add with: " "$CLIENT" "${CLIENT_PW:-$(pwgen -1 45)}"
#				client_add "$CLIENT" "${CLIENT_PW:-$(pwgen -1 45)}" "${CLIENT_INI_CONN:-${CLIENT_INI_CONN}}"
#				#echo "calling client_job with: " "${CLIENT} ${JOBDEF:-${DEFAULT_JOBDEF}} ${FILESET:-${DEFAULT_FILESET}}"
#				client_job "$CLIENT" "${JOBDEF:-${DEFAULT_JOBDEF}}" "${FILESET:-${DEFAULT_FILESET}}"
#				shift
#				break
#				;;
		esac
		echo "End of case Paramters:" "$@"
	done

	if [ "$1" == "" -a $FINISH_DOCU != "yes" ]; then
		echo "clientname missing, Aborting…" >&2
		exit 2
	elif [ "$1" != "" ]; then
		CLIENT=$1
		echo "NoOption Arg: '$1', Clientname: $CLIENT"
		echo "calling client_add with: " "$CLIENT" "${CLIENT_PW:-$(pwgen -1 45)}" "${CLIENT_INI_CONN:-${CLIENT_INI_CONN}}"
		client_add "$CLIENT" "${CLIENT_PW:-$(pwgen -1 45)}" "${CLIENT_INI_CONN:-${CLIENT_INI_CONN}}"
		echo "calling client_job with: " "${CLIENT} ${JOBDEF:-${DEFAULT_JOBDEF}} ${FILESET:-${DEFAULT_FILESET}}"
		client_job "$CLIENT" "${JOBDEF:-${DEFAULT_JOBDEF}}" "${FILESET:-${DEFAULT_FILESET}}"
		if [ "$CLIENT_INSTALL" = "yes" ];; then
			client_setup
		fi
	elif [ $FINISH_DOCU = "yes" ]; then
		finish_docu
		exit 
	fi

} #main

client_add() {
	if [ "$3"="yes" ]; then
		bconsole << EOF
configure add client \
  name=$1-fd \
  address=$1 \
  password=$2 \
  AutoPrune=yes \
  ConnectionFromClientToDirector=yes
reload
EOF
	sed -i "s/\}/  ConnectionFromClientToDirector = yes\n  \}/g" $BAREOS_EXPORT_DIR/client/${CLIENT}-fd/bareos-fd.d/director/${SERVER}-dir.conf
	else
		bconsole << EOF
configure add client \
  name=$1-fd \
  address=$1 \
  password=$2 \
  AutoPrune=yes
reload
EOF
	fi
echo "
## Client $1 added
\`\`\`
Hostname/IP:                $1
ClientPW:                   $2
Client Initiate Connection: $3
\`\`\`
" >> $CONFIG_DOC

} # client_add

client_job() {
	bconsole << EOF
configure add job \
  Enabled="yes" \
  Client="${1}-fd" \
  Name="backup-${1}-fd" \
  JobDefs="${2}" \
  FileSet="${3}" \
  Description="Standard hourly Backup"
reload
EOF

echo "
### ClientJob ${1}-fd added
\`\`\`
Hostname/IP: $1
JobDef:      $2
Fileset:     $3
\`\`\`
" >> $CONFIG_DOC

} # client_job

sshkey-check() {
	# generating SSH-keys
	[ -f $HOME/.ssh/id_rsa ] || {
		ssh-keygen -b 4049 -t rsa -f $HOME/id_rsa
	}
} # sshkey-check

client_setup() {
	# copy SSH-key to client

	echo "################################################################"
	echo "   Attention: Please give root@{CLIENT} Password, if asked for.
	echo "################################################################"

	ssh-copy-id root@${CLIENT}
	ssh root@${CLIENT} bash  << EOF
	apt-get update
	apt-get -y install bareos-client
	EOF

	# Copy Dirctory Stanza to Client
	scp  $BAREOS_EXPORT_DIR/client/${CLIENT}-fd/bareos-fd.d/director/$SERVER-dir.conf root@$CLIENT:/etc/bareos/bareos-fd.d/director/
	ssh root@${CLIENT} bconsole << EOF
	reload
	EOF

	echo "**Bareos-Client-SW installed**
	" >> $CONFIG_DOCU
}

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

# Note that we use "$@" to let each command-line parameter expand to a
# separate word. The quotes around "$@" are essential!
# We need TEMP as the 'eval set --' would nuke the return value of getopt.
TEMP=$(getopt -o 'cmlhsj:f:' -- "$@")

if [ $? -ne 0 ]; then
	echo 'Terminating...' >&2
	usage
		exit 1
fi

# Note the quotes around "$TEMP": they are essential!
eval set -- "$TEMP"
unset TEMP

# Main
main "$@"
