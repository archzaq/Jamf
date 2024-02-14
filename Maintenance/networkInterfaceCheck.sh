#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

wifiNetworkFound=0
IPsFound=0

findWiFi(){
    local wifi=$(networksetup -getairportnetwork $1)
    if [[ "$wifi" == "Current Wi-Fi Network"* ]];
    then
        ((wifiNetworkFound++))
    fi
}

findIPs(){
    local ethernet=$(ifconfig $1 | awk '/inet / {print $2}')
    if [ "$ethernet" ];
    then
        ((IPsFound++))
    fi
}

for each in $(networksetup -listallhardwareports | awk '/en/ {print $2}');
do
    findWiFi "$each"
    findIPs "$each"
done

if [ "$IPsFound" -eq 0 ];
then
    touch "/Library/Application Support/JAMF/Receipts/ethernetCheck_NoNetworks.txt"
    echo "Log: File created at: /Library/Application Support/JAMF/Receipts/ethernetCheck_NoNetworks.txt"
elif [ "$IPsFound" -eq 1 ];
then
    if [ "$wifiNetworkFound" -eq 1 ];
    then
        touch "/Library/Application Support/JAMF/Receipts/ethernetCheck_WiFi_Found.txt"
        echo "Log: File created at: /Library/Application Support/JAMF/Receipts/ethernetCheck_WiFi_Found.txt"
    else
        touch "/Library/Application Support/JAMF/Receipts/ethernetCheck_Ethernet_Found.txt"
        echo "Log: File created at: /Library/Application Support/JAMF/Receipts/ethernetCheck_Ethernet_Found.txt"
    fi
elif [ "$IPsFound" -eq 2 ];
then
    touch "/Library/Application Support/JAMF/Receipts/ethernetCheck_MultipleNetworks_Found.txt"
    echo "Log: File created at: /Library/Application Support/JAMF/Receipts/ethernetCheck_MultipleNetworks_Found.txt"
    echo "Log: $(echo "$wifiNetworkFound") WiFi networks found"
else
    touch "/Library/Application Support/JAMF/Receipts/ethernetCheck_ERROR.txt"
    echo "Log: Error! More than 2 IPs available"
fi

/usr/local/bin/jamf recon
