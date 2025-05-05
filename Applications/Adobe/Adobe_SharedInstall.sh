#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 05-05-24  ###
### Updated: 05-05-24  ###
### Version: 1.0       ###
##########################

/usr/bin/caffeinate -d &
CAFFEINATE_PID=$!
trap "kill $CAFFEINATE_PID" EXIT

/usr/local/bin/jamf policy -event sharedAdobe

exit 0
