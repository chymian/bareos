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
```
./install-client.sh -h
usage: install-client.sh [options] <clientname>
Setup a Job for client with the defaults JobDef: DefaultJob and FileSet: LinuxAll.
clientname can be a resolvable Hostname or an IP-Address.

   -c           Use "Client initiated Connections" for "not always on hosts", like Laptops, VM, etc.
   -f <fileset> Use FileSet <fileset> instaed of Default FileSet
   -h           Show this message.
   -j <jobdef>  Use Jobdef <jobdef> instaed of Default JobDef
   -l           List JobDefs and FileSets
   -m           Mail the updated Config-Docu and config-tarball (use as only switch)
   -s           Setup Client with bareos-fd & copy Director-definition to it

Docu & config-Tarball are not automatically updated.
Use "-m" on it's own at the end of your Setups to mail you the configs.
```

### Change BackupTime
* defaults to 20:00
```
TIME="19:00"
sed -i s/at ..:../$TIME/g /etc/bareos/bareos-dir.d/schedule/*
```
