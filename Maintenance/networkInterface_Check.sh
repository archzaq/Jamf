#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

wifiNetworkFound=0
IPsFound=0
ipList=()
noWifiList=()

findWiFi(){
    local wifi=$(networksetup -getairportnetwork $1)
    if [[ "$wifi" == "Current Wi-Fi Network"* ]];
    then
        wifiName=$(echo "$wifi" | awk '{print $4}')
        wifiIP=$(networksetup -getinfo Wi-Fi | awk '/IP address: / && !/IPv6/ {print $3}')
        ((wifiNetworkFound++))
    fi
}

findIPs(){
    local ip=$(ifconfig $1 | awk '/inet / {print $2}')
    if [ "$ip" ];
    then
        ipList+=("$ip")
        ((IPsFound++))
    fi
}

for each in $(networksetup -listallhardwareports | awk '/en/ && !/\(en/ {print $2}');
do
    findWiFi "$each"
    findIPs "$each"
done

for ip in "${ipList[@]}";
do
    if [[ "$ip" != "$wifiIP" ]];
    then
        noWifiList+=("$ip")
    fi
done

if [ "$IPsFound" -eq 0 ];
then
    touch "/Library/Application Support/JAMF/Receipts/ethernetCheck_NoNetworks.pkg"
    echo "Log: Error! How?"
    echo "Log: File created at: /Library/Application Support/JAMF/Receipts/ethernetCheck_NoNetworks.pkg"
elif [ "$IPsFound" -eq 1 ];
then
    if [ "$wifiNetworkFound" -eq 1 ];
    then
        touch "/Library/Application Support/JAMF/Receipts/ethernetCheck_WiFi_Found.pkg"
        echo "Log: Connected to $(echo "$wifiName") via Wi-Fi at $(echo "$wifiIP")"
        echo "Log: File created at: /Library/Application Support/JAMF/Receipts/ethernetCheck_WiFi_Found.pkg"
    else
        touch "/Library/Application Support/JAMF/Receipts/ethernetCheck_Ethernet_Found.pkg"
        echo "Log: Connected to ethernet at $(echo "${noWifiList[@]}")"
        echo "Log: File created at: /Library/Application Support/JAMF/Receipts/ethernetCheck_Ethernet_Found.pkg"
    fi
elif [ "$IPsFound" -ge 2 ];
then
    touch "/Library/Application Support/JAMF/Receipts/ethernetCheck_MultipleNetworks_Found.pkg"
    echo "Log: Connected to ethernet and WiFi"
    echo "Log: Connected to ethernet at $(echo "${noWifiList[@]}") and to $(echo "$wifiName") via Wi-Fi at $(echo "$wifiIP")"
    echo "Log: File created at: /Library/Application Support/JAMF/Receipts/ethernetCheck_MultipleNetworks_Found.pkg"
else
    touch "/Library/Application Support/JAMF/Receipts/ethernetCheck_ERROR.pkg"
    echo "Log: Error!"
fi

/usr/local/bin/jamf recon
