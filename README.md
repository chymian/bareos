# BareOS Backup System
see also: [BareOS Manual](http://doc.bareos.org/master/html/bareos-manual-main-reference.html#InstallChapter)

Using Openmediavault NAS-Server as Basesystem.  
At the time of writing, it's OMV Arrakis 4.0 on Debian 9 Stretch.

## Prerequisites
Create a Backup-Volume/Partiton on the RAID/Disk with label **backup**.  
The Volume with the Subvolume bareos will be mounted on ```/var/lib/bareos/``` to hold all BareOS relevant data-files.
```
BACKUP_VOL=/srv/dev-disk-by-label-backup
btrfs sub cr $BACKUP_VOL/bareos
btrfs quota enable $BACKUP_VOL/bareos/
btrfs sub cr $BACKUP_VOL/bareos/storage
btrfs quota enable $BACKUP_VOL/bareos/storage
btrfs sub cr $BACKUP_VOL/bareos/bootstrap
btrfs quota enable $BACKUP_VOL/bareos/bootstrap

grep -v "/var/lib/bareos" /etc/fstab > /tmp/fstab.tmp
printf "$BACKUP_VOL/bareos\t\t\t/var/lib/bareos\t\tnone\tbind\t0 0\n" >> /tmp/fstab.tmp

mv --backup=t /tmp/fstab.tmp /etc/fstab
mkdir -p /var/lib/bareos
mount /var/lib/bareos
```

## Installing BareOS from debian repo
No armhf packages in the BareOS-Repos, so we use older versions from Debian.
```
agi -y postgresql
agi -y bareos bareos-database-postgresql
chown -R bareos.  /etc/bareos /var/lib/bareos

# to use the directory-structure, remove old-style conf-files  
cd /etc/bareos
mv bareos-dir.conf .bareos-dir.conf
mv bareos-fd.conf .bareos-fd.conf
mv bareos-sd.conf .bareos-sd.conf
mv bareos-dir.conf.dist .bareos-dir.conf.dist
mv bareos-fd.conf.dist .bareos-fd.conf.dist
mv bareos-sd.conf.dist .bareos-sd.conf.dist
```
<div class="page-break"></div>

## Installing WebUI from Bareos-Repo

Using the WebUI from 16.2, which correspondes to Debian 8 @ the BareOS-Repo.  
```
# DIST=Debian_9.0
DIST=Debian_8.0
# DIST=xUbuntu_16.04

RELEASE=release/16.2
# or
# RELEASE=release/latest/
# RELEASE=experimental/nightly/

URL=http://download.bareos.org/bareos/$RELEASE/$DIST

# add the Bareos repository
printf "deb $URL /\n" > /etc/apt/sources.list.d/bareos.list

# add package key
wget -q $URL/Release.key -O- | apt-key add -

# install Bareos packages
apt-get update
apt-get install bareos-webui

# adjusting Apach2 to coexists with nginx
sed -i s/80/81/g ports.conf
sed -i s/443/8443/g ports.conf
a2dissite 000-default
service  apache2 restart
```

### Configure BareOS for WebUI  
```
service bareos-dir restart
service bareos-fd restart
service bareos-sd restart

WEBUI_ADM="admin"
WEBUI_PW=`pwgen -1 12`

bconsole << EOF
configure add console \
  name=$WEBUI_ADM \
  password=$WEBUI_PW \
  profile=webui-admin
reload
EOF
```
<div class="page-break"></div>

## Configuring BareOS
### Correcting Debian default configs  
Changing the default Client-/Director-/Monitor-Name from "bareos" to [Server-hostname]-dir|sd|fd
```
SERVER=`hostname`
cd /etc/baros
for i in `grep bareos-fd -lr * `; do sed -i s/bareos-fd/$SERVER-fd/g $i; done
for i in `grep bareos-dir -lr * `; do sed -i s/bareos-dir/$SERVER-dir/g $i; done
for i in `grep bareos-mon -lr * `; do sed -i s/bareos-mon/$SERVER-mon/g $i; done
for i in `grep bareos-sd -lr * `; do sed -i s/bareos-sd/$SERVER-sd/g $i; done
```

### Pool Definitions

#### Volume Retention
in ```/etc/bareos/bareos-dir.d/pool/```

* Full 4(2) months
* Differencial 2(1) months
* Incremental 1 months (14 days)
* LongTerm-Pool (Vacation) 12 months  

Limit Volume size and count to something reasonable, adjust per Pool:  
* Maximum Volume Bytes = XXG
* Maximum Volumes = XX  
* AutoPrune=yes
* ActionOnPurge=truncate
* Recycle=yes  

#### Create LongTerm-Pool
* Full 12 months
* manual start
```
bconsole << EOF
configure add pool \
  name=LongTermFull \
  pooltype=backup \
  recycle=yes  \
  maximumvolumebytes=50G \
  maximumvolumes=25 \
  volumeretention="12 months" \
  labelformat=LongTermFull- \
  autoprune=yes \
  ActionOnPurge=truncate \
  description="LongTerm Pool for 12 months Retention"
EOF
```

<div class="page-break"></div>

### Schedule  
in ```/etc/bareos/bareos-dir.d/schedule/```

#### WeeklyCycle Schedule
* defaults to 21:00

Change **mon** to **sun** in WeeklyCycle, to backup also on Sundays
```
sed -i s/mon/sun/g /etc/bareos/bareos-dir.d/schedule/WeeklyCycle.conf
```
Change **mon-fri at 21:10** to **daily at 22:00** in WeeklyCycleAfterBackup, to backup the Catalog every day.  
```
sed -i "s/mon-fri at 21:10/daily at 22:00/g" /etc/bareos/bareos-dir.d/schedule/WeeklyCycleAfterBackup.conf
```
Change Schedule-Time
```
TIME="19:00"
sed -i s/at ..:../$TIME/g /etc/bareos/bareos-dir.d/schedule/*
```


#### HourlyCycle Schedule
To be used as drop in replacement to WeeklyCycle, (same same, but hourly ;))
```
bconsole << EOF
configure add schedule \
  Enabled=yes \
  Name="HourlyCycle" \
  Run="Full 1st sat at 21:00" \
  Run="Differential 2nd-5th sat at 21:00" \
  Run="Incremental hourly at 0:22" \
  Description="Standard Schedule with Monthly=Full, Weekly=Diff, Hourly=Inc"
EOF
```

### Fileset
in ```/etc/bareos/bareos-dir.d/fileset/```  
**HINT:**  LZ4(HC)-Compression is supported from 16.2 @stretch – onwards.
Use GZIP with 14.2 – jessie (Debian 8) and Ubuntu 16.04
```
Include {
  Options {
    Signature=SHA1
    compression=gzip     # on 16.2 and later, use LZ4 or LZ4HC
    sparse = yes
    …
  }  
}
File = /
File = /home
#File = /srv/
#File = /var/lib/lxc
# and every LXC
#File = /var/lib/lxc/[Name of LXC]/rootfs

Exclude {
  …
  File = *.o
  File = /var/cache/apt/archives
}
```
#### The clever FileSet
```File = "\\|/bin/bash -c …" ``` runs on the client

```
# standard filessystems
cat /etc/fstab|egrep -v "^#|^$|swap|bind|iso|svfs|proc|tmp|devfs|sysfs|ram"|awk '{print $2}'|egrep -v "^/media|^/mnt|docker"
# @hansa,
# add /srv/media/music
# filter /srv/virt/images

# LXCs are backupd with host
# create a list of LXCs Direcotory & rootfs
# /var/lib/lxc/apps
# /var/lib/lxc/apps/rootfs

lxc-ls -1|awk '{ printf "/var/lib/lxc/"$1"\n""/var/lib/lxc/"$1"/rootfs\n" }'


# create a list out of the LXCs mount-entrys of bind-mounted volumes from /mnt
grep -s  bind /var/lib/lxc/*/*|egrep -v "\.log|proc|sysfs|tmp" | cut -d":" -f2 | sed s/.*mount.*\ =\ //g|awk '{ print $1 }'|sort -u|grep "^/mnt/"


# VPS are backuped from within -> REAR

```

For "One FS = yes" add  
```
File = /home
File = /srv
File = /var/lib/lxc
# and every LXC
File = /var/lib/lxc/coiner/rootfs
```

### JobDefs  
* Create Hourly-JobDef
* Create LongTerm-JobDef
* Accurate = yes
* Write Bootstrap = "/var/lib/bareos/**bootstrap**/%c.bsr"
```
sed -i s#/var/lib/bareos/\%c#/var/lib/bareos/bootstrap/\%c#g \
  /etc/bareos/bareos-dir.d/jobdefs/*
```
#### Add JobDef: DefaultJob-Hourly  
```
bconsole << EOF
configure add jobdefs \
  Enabled="yes" \
  Name="DefaultJob-Hourly" \
  Type="Backup" \
  Level="Incremental" \
  Accurate="yes" \
  Schedule="HourlyCycle" \
  Storage="File" \
  Messages="Standard" \
  Pool="Incremental" \
  Priority="10" \
  WriteBootstrap="/var/lib/bareos/bootstrap/%c.bsr" \
  FullBackupPool="Full" \
  DifferentialBackupPool="Differential" \
  IncrementalBackupPool="Incremental"
reload
EOF
```

#### Add JobDef: LongTermFull  
```
bconsole << EOF
configure add jobdefs \
  Enabled="yes" \
  Name="LongTermFull" \
  Type="Backup" \
  Level="Full" \
  Accurate="yes" \
  Storage="File" \
  Messages="Standard" \
  Pool="LongTermFull" \
  Priority="10" \
  WriteBootstrap="/var/lib/bareos/bootstrap/%c.bsr" \
  FullBackupPool="LongTermFull"
reload
EOF
```

### Jobs  
* Create a Job for every Client
* Create a LongTermFull Job for Longterm (Vacation) Retention.  
  * schedule  
  This directive is optional, and if left out, the Job can only be started manually using the Console program.  
* filesets in Jobs
#### File & Catalog-Retention
Check File & Catalog Retention Values.  
per job-type for
* WS
* VPS
* LXCs

#### Add a Job: LongTermFull
```
CLIENT=[your CLIENT hostname here]
bconsole << EOF
configure add job \
  Enabled="yes" \
  Name="LongTermFull" \
  JobDefs="LongTermFull" \
  Client="$CLIENT-fd" \
  FileSet="LinuxAll" \
  Description="Full Backup for longterm Retention"
reload
EOF
```

<div class="page-break"></div>

## Installing a Client  

### Software Installation  
@Client
```
agi -y bareos-client pwgen
# with gui
agi -y bareos-traymonitor

cd /etc/bareos
SERVER=[your servername here]

# BareOS 16.2 or later
rm /etc/bareos/bareos-fd.d/director/bareos-dir.conf
for i in `grep bareos-dir -lr * `; do sed -i s/bareos-dir/$SERVER-dir/g $i; done
for i in `grep bareos-mon -lr * `; do sed -i s/bareos-mon/$SERVER-mon/g $i; done

# Bareos 14.2
sed -i s/bareos-dir/$SERVER-dir/g bareos-fd.conf bconsole.conf
sed -i s/bareos-mon/$SERVER-mon/g bareos-fd.conf bconsole.conf
```

### Define the Client at BareOS Director  
@Server
```
CLIENT=[your clientname here]
SERVER=`hostname`
PASSWORD=`pwgen -1 45`

bconsole << EOF
  configure add client \
  name=$CLIENT-fd \
  address=$CLIENT \
  password=$PASSWORD \
  AutoPrune=yes
reload
EOF
```
### Add Director-Definition to the Client
BareOS 16.2 and later
@server
```
scp /etc/bareos/bareos-dir-export/client/${CLIENT}-fd/bareos-fd.d/director/$SERVER-dir.conf \
 root@$CLIENT:/etc/bareos/bareos-fd.d/director/
```

BareOS 14.2
@client
```
SERVER=[your servername here]
CLIENT=`hostname`
cd /etc/bareos
sed -i s/$CLIENT-dir/$SERVER-dir/g bareos-fd.conf
sed -i s/$CLIENT-mon/$SERVER-mon/g bareos-fd.conf
# Take PASSWORD from Above and change it in the $SERVER-dir stanza in bareos-fd.conf
service bareos-fd restart
```

### Add a Client Job  
@Server  
```
CLIENT="[IP or hostname]"

bconsole << EOF
configure add job \
  Enabled="yes" \
  Client="$CLIENT-fd" \
  Name="backup-$CLIENT-fd" \
  JobDefs="DefaultJob-Hourly" \
  FileSet="LinuxAll" \
  Description="Standard hourly Backup"
reload
EOF
```

### Run first Client Backup  
```
bconsole
* run
```

<div class="page-break"></div>

## ToDo  
* LongTerm retentionTime must be longer then longest Vacation
* Base Backups  

#### Writing Bootstrap files (to REAR-USB?)
Create better bootstrap-files and copy them to REAR-USB.  
see [about bootstrap files](http://doc.bareos.org/master/html/bareos-manual-main-reference.html#x1-555000D)

#### Backing up VPS & LXCs
* Create a Fileset and JobDef for LXCs & VPS

see [FileSet Definitions](http://doc.bareos.org/master/html/bareos-manual-main-reference.html#QQ2-1-226)  
either use (raw) image-backup @HOST or use  

##### Client initiated Connections for NotAlwaysOn VPS/LXCs
in **/etc/bareos/bareos-dir.d/clients/** or per bconsole add to the usual client cmd:

```
Name = <client>-fd
Address = <client> or IP
Password = <password>
Connection From Client To Director = yes     # to start backups from client
```

To only allow Connection From the Client to the Director use:
* Connection From Director To Client Dir Client = no
* Connection From Client To Director Dir Client = yes
* Heartbeat Interval Dir Client = 60 # to keep the network connection established
* Connection From Director To Client Fd Director = no
* Connection From Client To Director Fd Director = yes


#### Snapshotting System for Backups
see job(defs)
* Cient Run Before Job
* Client Run After Job
* Run Script

Fileset Definitions
* strippath=[integer] in the [FileSet Definitions](http://doc.bareos.org/master/html/bareos-manual-main-reference.html#QQ2-1-226)

<div class="page-break"></div>

## Usefull Cmds

**ATTENTION:** use with Care

#### Delete All Jobs of all clients
```
for i in `echo list clients |bconsole|tail  -n8|awk '{print $4}'`; do
  echo purge jobs client=$i|bconsole
done
```
#### Truncate all Volumes in All Pools
To ask Bareos to truncate your Purged volumes, you need to use the following:
```
for i in `echo list pools |bconsole|tail  -n8|awk '{print $4}'`; do
  echo "purge volume action=truncate storage=File pool=$i"|bconsole
done
```
