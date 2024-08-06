#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 8-1-24    ###
### Updated: 8-6-24    ###
### Version: 1.0       ###
##########################

if [ -z "$1" ];
then
    echo "add a username to be deleted"
    exit 0
fi

sudo sysadminctl -deleteUser "$1" -secure
