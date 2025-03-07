#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 8-1-24    ###
### Updated: 8-6-24    ###
### Version: 1.0       ###
##########################

if [ -z "$1" ];
then
    echo "add a username to check secure token status"
    exit 0
fi

sysadminctl -secureTokenStatus "$1"
