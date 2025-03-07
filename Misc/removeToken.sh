#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 8-1-24    ###
### Updated: 8-6-24    ###
### Version: 1.0       ###
##########################

# Run this script with two parameters, the first username is the account to
# remove the secure token for, the second account is the admin account

if [ -z "$1" ];
then
    echo "add a username to remove token"
    exit 0
fi

if [ -z "$2" ];
then
    echo "add an admin user name"
    exit 0
fi

sudo sysadminctl -secureTokenOff "$1" -adminUser "$2" -adminPassword - -password -
