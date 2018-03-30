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
	echo "usage: $(basename $0) [options] <clientname>
Setup a Job for client with the defaults JobDef: $DEFAULT_JOBDEF and FileSet: $DEFAULT_FILESET.
clientname can be a resolvable Hostname or an IP-Address.

   -c		Use \"Client initiated Connections\" for \"not always on hosts\", like Laptops, VM, etc.
   -f <fileset> Use FileSet <fileset> instaed of Default FileSet
   -h           Show this message.
   -j <jobdef>  Use Jobdef <jobdef> instaed of Default JobDef
   -l           List JobDefs and FileSets
   -m           Mail the updated Config-Docu and config-tarball (use as only switch)
   -s           Setup Client with bareos-fd & copy Director-definition to it

Docu & config-Tarball are not automatically updated.
Use \"-m\" on it's own at the end of your Setups to mail you the configs.

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
		#echo "Anz: $#; i = $i; Para:" "$@"
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
				continue
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
				continue
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
		#echo "NoOption Arg: '$1', Clientname: $CLIENT"
		#echo "calling client_add with: " "$CLIENT" "${CLIENT_PW:-$(pwgen -1 45)}" "${CLIENT_INI_CONN:-${CLIENT_INI_CONN}}"
		client_add "$CLIENT" "${CLIENT_PW:-$(pwgen -1 45)}" "${CLIENT_INI_CONN:-${CLIENT_INI_CONN}}"
		#echo "calling client_job with: " "${CLIENT} ${JOBDEF:-${DEFAULT_JOBDEF}} ${FILESET:-${DEFAULT_FILESET}}"
		client_job "$CLIENT" "${JOBDEF:-${DEFAULT_JOBDEF}}" "${FILESET:-${DEFAULT_FILESET}}"
		if [ "$CLIENT_SETUP" = "yes" ]; then
			client_setup ${CLIENT}
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
	# add CIC & Address in exported-file
	sed -i "s/\}/  ConnectionFromClientToDirector = yes\n  Address = ${SERVER}\n}/g" $BAREOS_EXPORT_DIR/client/${CLIENT}-fd/bareos-fd.d/director/${SERVER}-dir.conf
	# Create Logfile entry in Standard-Message file for client
	mkdir -p ${BAREOS_EXPORT_DIR}/client/${CLIENT}-fd/bareos-fd.d/messages
	cat << EOF > ${BAREOS_EXPORT_DIR}/client/${CLIENT}-fd/bareos-fd.d/messages/Standard.conf
Messages {
  Name = Standard
  Director = ${SERVER}-dir = all, !skipped, !restored
  Description = "Send relevant messages to the Director."
  Append = "/var/log/bareos/bareos-fd.log" = all, !skipped, !restored
}
EOF
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
	sed -i "s/Password =.*/Password = $2/g" $BAREOS_EXPORT_DIR/client/${CLIENT}-fd/bareos-fd.d/director/${SERVER}-dir.conf
echo "
## Client $1 added
Date:            `date`

\`\`\`
Hostname/IP:                  $1
ClientPW:                     $2
Client initiated Connections: $3
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

sshkey_check() {
	# generating SSH-keys
	[ -f $HOME/.ssh/id_rsa ] || {
		ssh-keygen -b 4049 -t rsa -f $HOME/id_rsa
	}
} # sshkey-check

client_setup() {
	sshkey_check
	CLIENT=$1
	# copy SSH-key to client

	echo
	echo "##################################################################"
	echo "   Attention: Please give root@${CLIENT} Password, if asked for."
	echo "##################################################################"
	echo

	ssh-copy-id root@${CLIENT} || {
		echo err: No sshkey copy possible, Password-Auth blocked from $CLIENT
		echo Please copy your ssh-keys manualy over.
		exit 3
	}
	ssh root@${CLIENT} bash  << EOF
apt-get update >> /dev/null
apt-get -y install bareos-client
EOF

	# Config-File layout according to Verseion
	# <= 14.2 == file-structur
	# >= 16.2 == directory-structur
	#if [[ $(echo ${BAREOS_INFO[2]}) >= 16 ]] ; then
		# Copy Dirctory Stanza to Client
		rsync -r  $BAREOS_EXPORT_DIR/client/${CLIENT}-fd/bareos-fd.d root@$CLIENT:/etc/bareos/
		ssh root@${CLIENT} bash << EOF
chown -R bareos. /etc/bareos
service bareos-fd restart
EOF
#	else
#		cat $BAREOS_EXPORT_DIR/client/${CLIENT}-fd/bareos-fd.d/director/${SERVER}-dir.conf|grep -v "ConnectionFromClientToDirector"\ 
#		| ssh root@coiner16 'cat >> /etc/bareos/bareos-fd.conf'
#		ssh root@${CLIENT} bash << EOF
#chown -R bareos. /etc/bareos
#service bareos-fd restart
#EOF
#	fi
	echo "## Bareos-Client-SW installed
\`\`\`
ClientSW installed:   yes
\`\`\`

***
" >> $CONFIG_DOC
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
