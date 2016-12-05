# DUPLY TO TAHOE-LAFS: EASY INCREMENTAL BACKUP TO ENCRYPTED & DECENTRALISE GRID OF RASPBERRY PI 3 #

![duply-tahoe.png](https://github.com/gregbkr/duply-tahoe-docker/raw/master/duply-tahoe.png)

Duply: 
- runs backup on host which has the ssh keys to access other servers
- uses duplicity/rsync to incrementally backup local/remote folder
- can encrypt (or leave the task to backend) 
- sends backup to backend:
   - Tahoe LAFS: a decentralysed encrypted storage grid made of Raspberry/homepc/server (full doc below)
   - AWS S3: S3 classic bucket (few steps in end of document)

More info: you can find an overview of that setup on my blog: https://greg.satoshi.tech/

# 1. Get all files from github and build the container

    cd /root/ && git clone https://bitbucket.org/sbex/duply.git && cd duply
    docker build -t duply .

# 2. Tahoe storage grid

You can build the storage grid on the same server for testing, or different one for production. Follow the graph to see which port to open.

## 2.1 Introducer: 
Connector/hub/directory which will list all available storages. Where our client will get the list of all available storages.

Initialize:

    docker run --rm -v /root/.introducer:/root/.introducer/ dockertahoe/tahoe-lafs tahoe create-introducer --basedir=/root/.introducer --port=tcp:41464 --location=tcp:<YOUR_LOCAL_IP>:41464

Run container:

    docker run -d --name tahoe-introducer -p 41464:41464 -v /root/.introducer:/root/.introducer/ tdockertahoe/tahoe-lafs tahoe start /root/.introducer --nodaemon --logfile=-

Get the introducer url and replace --introducer in next commands!!

    docker exec tahoe-introducer cat /root/.introducer/private/introducer.furl


## 2.2 Storage server
Grid nodes where all the actual data will be. It can be raspberry, server, homepc.

### 2.2.1 For linux box use:

Initialize:

    docker run --rm -v /root/.storage:/root/.storage/ dockertahoe/tahoe-lafs tahoe create-node --basedir=/root/.storage --nickname=`hostname` --port=tcp:3457 --location=tcp:<YOUR_LOCAL_IP>:3457 --introducer=pb://zyadrwuf....

Run container:

    docker run -d --name tahoe-storage -p 3457:3457 -v /root/.storage:/root/.storage/ dockertahoe/tahoe-lafs tahoe start /root/.storage --nodaemon --logfile=-

Same config on other storage servers...

### 2.2.2 Storage server on raspberry pi (raspian)

What you need:
- Ubuntu laptop to load the pi os to a SD card
- Access to your home router configuration (for port forwarding)
- Network cable (prefered) or wifi access

Note: this only thing missing so far in my doc is how to connect an external HD for more storage. We will use only SD storage for the moment.

Download raspian image:

    cd Downloads && wget https://downloads.raspberrypi.org/raspbian_lite_latest

Unmount all SD card drive
```
df -h
/dev/sdb1                       40862   22414     18448  55% /media/gg/resin-boot
/dev/sdb2                      174392  134814     30362  82% /media/gg/resin-root
/dev/sdb5                       20422       2     20420   1% /media/gg/resin-conf
/dev/sdb6                    15115776  919240  13766776   7% /media/gg/resin-data
```
    sudo umount /dev/sdb1  (2,5,6)

(Not needed: if you want to format your partition: sudo mkdosfs -F 32 -v /dev/sdb)

Install OS (https://www.raspberrypi.org/documentation/installation/installing-images/linux.md)

    cd Downloads 
    sudo dd bs=4M if=2016-09-23-raspbian-jessie-lite.img of=/dev/sdb

If wifi only: edit your local wifi networks:

    sudo nano /media/gg/3598ef8e-09be-47ef-9d01-f24cf61dff1d/etc/wpa_supplicant/wpa_supplicant.conf
    country=CH
    network={
        ssid="KSYS_bdc7"
        psk="moS2QEUa8t2fM"
    }

Edit keyboard
    sudo nano /media/gg/3598ef8e-09be-47ef-9d01-f24cf61dff1d/etc/default/keyboard 
    XKBLAYOUT="ch"

Edit hostname with your nickname/location

    sudo nano /media/gg/3598ef8e-09be-47ef-9d01-f24cf61dff1d/etc/hostname
    greghome-pi

    sudo nano /media/gg/3598ef8e-09be-47ef-9d01-f24cf61dff1d/etc/hosts
    127.0.0.1 greghome-pi

    sudo umount /dev/sdb1  (2,5,6)

At home: put sd card in rasberry and start it. Wait and scan (before and after) the network to find his ip:

    nmap -sP 192.168.1.0/24

Or you can connect to your home router and check the dhcp.

Connect to it

    ssh pi@YOUR_RASPBERRY_IP  (password: raspberry)

Install docker

    sudo apt-get update -y
    sudo apt-get dist-upgrade -y
    sudo shutdown -r
    sudo curl -sSL https://get.docker.com | sh

Dockerfile:
    
    sudo nano /home/pi/Dockerfile

```
FROM resin/rpi-raspbian:jessie
MAINTAINER gregbkr@outlook.com

RUN apt-get update && \
    apt-get install -y git python-pip build-essential python-dev libffi-dev libssl-dev python-virtualenv

RUN git clone https://github.com/tahoe-lafs/tahoe-lafs
ADD . /tahoe-lafs
RUN \
  cd /tahoe-lafs && \
  git pull --depth=100 && \
  pip install . && \
  rm -rf ~/.cache/

RUN tahoe --version

WORKDIR /root
```

Build images

    sudo docker build -t tahoe-arm .

Add settings:
YOUR_PUBLIC_IP --> at home, find your public IP here: https://www.whatismyip.com/what-is-my-public-ip-address/

    sudo docker run --rm -v /home/pi/.tahoe:/root/.tahoe/ tahoe-arm tahoe create-node --nickname=`hostname` --port=tcp:3457 --location=tcp:<YOUR_PUBLIC_IP>:3457 --introducer=pb://zya.....

Run tahoe storage

    sudo docker run -d --name tahoe-storage -p 3457:3457 -v /home/pi/.tahoe:/root/.tahoe/ tahoe-arm tahoe start /root/.tahoe --nodaemon --logfile=-
    sudo docker logs tahoe-storage

Activate your home router redirection:
```
Name            : tahoe
Protocal        : TCP
IP source       : *              <- access from internet
Port source     : 3457           <- port of the router to be redirected internally
IP destination  : 192.168.1.33   <- your raspberry local IP
Port destination: 3457
```

Test with: (should get a filtered/open state at least)

    nmap YOURPUBLIC_IP_ADDRESS -p 3456 -Pn


## 2.3 Storage client
This is the backup server: no backup files here, but all secrets are here. We will run backup and restore from here. So this container got tahoe-client and duply. 

Initialize tahoe-client and use the introducer url from your grid:

    docker run --rm -v /root/.tahoe:/root/.tahoe/ duply \
        tahoe create-client \
            --nickname=`hostname` --webport=tcp:3456:interface=0.0.0.0 \
            --introducer=pb://zyadrw....

    nano /root/.tahoe/tahoe.cfg  <-- change shares.happy=2(minimum storage needed) if your have only 2 storage server. 

Run duply + tahoe-client container:

    docker run -d --name duply \
        -v ~/.ssh:/ssh -v /root/.gnupg:/root/.gnupg -v /root/.duply:/root/.duply -v /root/backup:/root/backup \
        --cap-add SYS_ADMIN --device /dev/fuse --privileged \
        -p 3456:3456 \
        -v /root/.tahoe:/root/.tahoe \
        duply

Note: 
  - always edit config on the host, and use docker restart duply to refresh container if needed
  - --cap-add, --device, --priviledged: is to be able to backup remote folder via sshfs
  - -v /ssh, .gnupg: share the host key to container duply

At this point your can see all your node in the admin GUI on <storageclient_ip>:3456

![tahoe-admin.png](https://github.com/gregbkr/duply-tahoe-docker/raw/master/tahoe-admin.png)

Create(or import an existing) tahoe alias: it is the root folder where we will make backup.

    docker exec duply tahoe create-alias backup
    docker exec duply tahoe list-aliases
    backeup: URI:DIR2:pmhosio65ugrucuvyt4uminbnq:7msac6ypv6nl5z33ionhaenzcrqutpycatuzgix7462nafgqtegq   <-- KEEP THIS URI REF, ONLY WAY TO RECOVER YOUR BACKUPS!

Physical location of these keys on hosts:

    nano /root/.tahoe/private/aliases

You can create subfolder this way:

    docker exec duply tahoe mkdir backup:test
    URI:DIR2:x5azfaectlywtchb2nddagxxwi:mhk3ehghys3t2oahjelolsppfbpf2iu67uvg2yiv36afqncodgna

If you give a subfolder link to someone, they can not dedure or see the root folder. 

To connect to an already existing tahoe alias: 

    docker exec duply tahoe add-alias backup URI:DIR2:pmhosio65ugrucuvyt4uminbnq:7msac6ypv6nl5z33ionhaenzcrqutpycatuzgix7462nafgqtegq

List content of folder backup:

    docker exec duply tahoe ls backup:

Test backup:

Open tahoe admin GUI:

Open Tahoe-URL > URI:DIR2:ohqbr6easltpe7m7xf6lw47stm:2hpnrrtnxchhvokfqrjujlobbikowvbdy6z3dsod2ajo7y4s3vha > View file or directory

Upload a file. Now you can see that if you don't provide that long URI, it is impossible to see the file. 
If you upload a file without providing any URI, tahoe will generate a new URI. Don't loose that URI, or you can't recover your files.


# 3. Duply

## 3.1 Setup duply test conf
Duply container should already be running, or see on top the section: "Run duply + tahoe-client container"

Create a test config:

    docker exec duply duply test create

    nano /root/.duply/test/conf   <-- replace with the value below
    # tahoe
    TARGET='tahoe://backup/'
    # base directory to backup
    SOURCE='/root/backup/'
    # GPG
    GPG_KEY='disabled'  # <-- tahoe take care of encryption
    # GPG_PW=
    DUPL_PARAMS="$DUPL_PARAMS --allow-source-mismatch "   # <-- usefull because duply we work in a container which can be delete


Create a test file to test a backup:

   touch "backup test 1" > /root/backup/test1

Run a backup to tahoe

    docker exec duply duply test backup    (--allow-source-mismatch could be needed if error)

Check backup via Duply

    docker exec duply duply test list --disable-encryption

Check file are present in Tahoe via GUI or command line (you should see few duplicity... files)

    docker exec duply tahoe ls backup:


## 3.2 Quick commands

Backup

    docker exec duply duply YOUR_BCK_PROFILE backup    (if needed: --disable-encryption --allow-source-mismatch)

List

    docker exec duply duply YOUR_BCK_PROFILE list

restore

    docker exec duply duply YOUR_BCK_PROFILE restore /root/backup/YOUR_CHOICE_restore

list backup of x time ago: s, m, h, D, W, M, or Y (indicating seconds, minutes, hours, days, weeks, months, or years respectively)   http://duplicity.nongnu.org/duplicity.1.html

    docker exec duply duply YOUR_BCK_PROFILE list --time 10m
    docker exec duply duply YOUR_BCK_PROFILE list --time 2W  

List backup collection in tahoe

    docker exec duply duplicity collection-status tahoe://backup

restore last version    

    docker run --rm -v /root/duply/.duply:/root/.duply -v /root/restore:/root/restore duply YOUR_BCK_PROFILE restore /root/backup/YOUR_RESTORE_FOLDER
    
restore version of 10 min ago.  

    docker run --rm -v /root/duply/.duply:/root/.duply -v /root/restore:/root/restore duply ethereum restore /root/restore/ethereum --time 10m


## 3.3 Typical backup profile

Usually, important file to backup are not on the backup server. So I use ssh to run command like pg_dump for exemple, before to retrieve the files via sshfs.

cp -r /root/.duply/test /root/.duply/postgres

Edit main conf:

    nano /root/.duply/postgres/conf

    # tahoe
    TARGET='tahoe://backup/'

    # base directory to backup
    SOURCE='/mnt/backup'    #<-- for remote backup with sshfs

    # GPG
    GPG_KEY='disabled'  # <-- tahoe take care of encryption
    #GPG_PW='_GPG_PASSWORD_'

    ## Backup retention: need to use purge to remove old backup. Help: https://zetta.io/en/help/articles-tutorials/backup-linux-duply/
    # MAX_AGE=              is how far back in time you want backups to be kept
    # MAX_FULL_BACKUPS=     is how many full backups we want to keep
    # MAX_FULLS_WITH_INCRS= is how many full backups with incremental backups we want to keep
    # MAX_FULLBKP_AGE=      is how long we should to incremental backups before we need to do a full backup

    MAX_AGE=12M
    #MAX_FULL_BACKUPS=6
    #MAX_FULLS_WITH_INCRS=1
    MAX_FULLBKP_AGE=1W

    DUPL_PARAMS="$DUPL_PARAMS --full-if-older-than $MAX_FULLBKP_AGE --allow-source-mismatch "

Edit script PRE which will be executed before the backup (please change VM and CONTAINER var)

    nano /root/.duply/postgres/pre

    #!/bin/bash
    VM=185.19.x.x
    CONTAINER=dbmaster
    DATE=$(date +%Y-%m-%d)

    mkdir -p /mnt/backup

    echo "--> postgres: pg_dump"
    ssh -o StrictHostKeyChecking=no -i /ssh/id_rsa_sbexx root@$VM mkdir -p /root/backup
    ssh -o StrictHostKeyChecking=no -i /ssh/id_rsa_sbexx root@$VM bash -c \" docker exec -t -u postgres $CONTAINER pg_dumpall -c \| gzip --rsyncable \> /root/backup/postgres-pgdump.gz \"

    echo "--> Mount remote backup folder to local duply container"
    sshfs -o StrictHostKeyChecking=no -oIdentityFile=/ssh/id_rsa_sbexx root@$VM:/root/backup /mnt/backup
    ls -lah /mnt/backup

Edit script POST which will be executed after the backup

    nano /root/.duply/postgres/post

    #!/bin/bash
    umount /mnt/backup

Run a Backup 

    docker exec duply duply postgres backup


# 4. Maintenance

## 4.1 Backup the backup server

You need to backup in a save place the following files:

- /root/.tahoe
- /root/.duply
- pgp keys & password (If you are using gpg: see section below)

IMPORTANT: Please make few backups. Then try to restore the system on another host to be sure to cover a disaster recovery!!

## 4.2 Tahoe

To reconstruct the backup, if one node goes offline, or one new node get added: (run every day by cron)

    docker exec duply duply tahoe deep-check --repair backup:

## 4.3 Crontab

    # duply: backups
    00 00 * * * /usr/bin/docker exec duply duply test backup | tee --append /root/logs/duply-test.log > /dev/null 2>/dev/null
    # Tahoe: maintenance
    00 03 * * 1 docker exec duply duply tahoe deep-check --repair backup:  | tee --append /root/logs/tahoe-maintenance.log > /dev/null 2>/dev/null

# 5. ANNEXES

## 5.1 To encrypt with pgp keys the backup: (not needed as tahoe already encrypt)

Use the provided one for test:

    gpg --import /root/files/gpgtest.DC581D8A.pub.asc.export
    gpg --import /root/files/gpgtest.DC581D8A.pri.asc.export

Or create new one for prod:

    gpg --gen-key
    for exemple: name:backuptest, email:backuptest@gmail.com, pw: geneva2016

Backup your keys: save in a save place these 2 files + folder + your_password

    gpg --export-secret-keys -a keyid > backup_private_key.asc
    gpg --export -a keyid > backup_public_key.asc
    ~/.gnupg
    
trust the key

   gpg --edit-key DC581D8A

> trust

> 5 (select 5 if you ultimately trust the key) 

> y

Check the key

    gpg --list-key

    ------------------------------
    pub   2048R/DC581D8A 2016-03-29
    uid                  backuptest <backuptest@gmail.com>
    sub   2048R/B380730B 2016-03-29

In duply conf:

    # gpg encryption:
    GPG_KEY='DC581D8A'
    GPG_PW='geneva2016'


## 5.2 Duply backup to S3 backend

You need to have a bucket ready on AWS or Exoscale and edit .duply/YOUR_BCK_PROFILE/conf

    # for s3 exoscale
    TARGET='s3://sos.exo.io/backup-duply/test'
    TARGET_USER='w_Y9G_G22bldi9q....'
    TARGET_PASS='X_haTCVy6q4UQJBS...'

    # for s3 aws
    TARGET='s3://s3-us-west-2.amazonaws.com/backup-duply/test'
    TARGET_USER='AKIAJ....'
    TARGET_PASS='KUgmx....'
