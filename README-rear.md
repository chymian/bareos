# Disaster Recovery with ReaR and BareOS

## Prerequisites
A working BareOS Backup-Server with backups already made.
A working Bconsole-Connection to the BareOS-Server.
Disaster Recovery does not work with BareOS 14.2.

## Installing
Rear is in testing/buster Repo availlable from debian, or get it from [relax-and-recover.org](http://relax-and-recover.org/download/)
```
echo "deb http://httpredir.debian.org/debian/ buster main contrib non-free" > /etc/apt/sources.list.d/buster.list
apt-get update
apt-get install -y rear extlinux
```

### Configuration
```
CLIENT=`hostname`
cat << EOF > /etc/rear/local.conf
#
# Sample Configfile for ReaR & BareOS
#

# Output of Bootfile/ISO
OUTPUT=USB
USB_DEVICE=/dev/disk/by-label/REAR-000

# ext. Backup System
BACKUP=BAREOS
#BAREOS_CLIENT=${CLIENT}-fd
# Only if you have more than one fileset defined for your clients backup jobs,
# you need to specify which to use for restore.
# or: if fileset does not have hostname in it's name, specify it
BAREOS_FILESET=LinuxAll
EOF
```


### Create a Rescue-USB-Stick
Bios-Boot  
```
DEV=/dev/sdc
rear format $DEV
rear -v mkrescue
```
EFI-Boot  
```
DEV=/dev/sdc
rear format -- --efi $DEV
rear -v mkrescue
```

## Disaster Recovery
Boot the BareMetal from the Rescue-USB-Stick.

### Full automated Restore
In the bootmenu, select:

***Recovery images***
 -> **[your hostname]**
  --> **[latest] rescue image - AUTOMATIC RECOVER**

* Wait till the restore has finished. REAR asks you to check the restored Files under `/mnt/local` – do it, or
* just type `exit` to continue  
* reboot
