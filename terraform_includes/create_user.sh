#!/usr/bin/env bash

USERNAME=mariadb
GROUPNAME=mariadb
ROCKY=/home/rocky
CENTOS=/home/centos
UBUNTU=/home/ubuntu
ORACLE=/home/ec2-user
NEW=/home/$USERNAME
KEYS=.ssh/authorized_keys
SUDOERFILE=/etc/sudoers.d/$USERNAME

sudo useradd $USERNAME &> /dev/null
sudo groupadd $GROUPNAME &> /dev/null
sudo usermod -a -G $GROUPNAME $USERNAME
sudo mkdir -p "$NEW/.ssh"
sudo chown -R $USERNAME:$GROUPNAME $NEW

if [ -d "$ROCKY" ]; then
    sudo cp $ROCKY/$KEYS $NEW/$KEYS
fi

if [ -d "$CENTOS" ]; then
    sudo cp $CENTOS/$KEYS $NEW/$KEYS
fi

if [ -d "$UBUNTU" ]; then
    sudo cp $UBUNTU/$KEYS $NEW/$KEYS
fi

if [ -d "$ORACLE" ]; then
    sudo cp $ORACLE/$KEYS $NEW/$KEYS
fi

sudo chown -R $USERNAME:$GROUPNAME $NEW
sudo chmod +400 $NEW/$KEYS
sudo echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" | sudo tee $SUDOERFILE &> /dev/null
sudo chmod +440 $SUDOERFILE
