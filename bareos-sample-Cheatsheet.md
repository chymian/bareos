# eb8's BareOS install Cheatsheet

This is based on an armbian based Openmediavault Installation, but should work on any Debian Stretch or newer.

## Prerequisites  
Minimum Setup for OMV:  
1) Change WEB-Admin Password  
2) Enable NTP  
3) Setup Hostname & Domain  
4) Setup Network-Interface  
5) Setup eMail-Notifications in OMV: the install script sends the installation Protocol & a tarball of /etc/bareos upon completion.
6) Create a Backup-Partiton on the RAID/Disk with label **backup** and mount it.  
7) Enable SSH root login.  
8) SSH to the server as root and run ./run-once.sh (on Armbian/OMV only).  

## Install the BareOS Server  
This installes the BareOS-Server with WebUI and a set of Sample-Configs ready to be used with Clients, which are installed in the next step.
```
git clone https://github.com/chymian/bareos.git
cd bareos
./install.sh
```
During Installation of the PostGreSQL, you get asked some Questions:  
Use the Defaults, note down your password.

## Install Clients  

…
## How to Customize the BareOS-sample Config
from https://github.com/chymian/bareos-sample.git

maybe: check:
### Storage Definitions
In ```/etc/bareos/bareos-dir.d/storage/File.conf``` set Address = [hostname]
```
SERVER=`hostname`
sed -i "s/Address = .*/Address = $SERVER/g" /etc/bareos/bareos-dir.d/storage/File.conf
```

### Change BackupTime
* defaults to 20:00
```
TIME="19:00"
sed -i s/at ..:../$TIME/g /etc/bareos/bareos-dir.d/schedule/*
```
