#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 8-1-24    ###
### Updated: 8-6-24    ###
### Version: 1.0       ###
##########################

user=$(whoami)
sourcePath="/Users/$user/Documents/Bitlocker Recovery Keys"
destPath="/Users/$user/Documents/AllBitLockerKeys"
fileCount=0

mkdir -p "$destPath"

find "$sourcePath" -type f | while IFS= read -r file;
do
    ((fileCount++))
    fileName=$(basename "$file")
    if [ -f "$file" ];
    then
        cp "$file" "$destPath"
        echo "Copied $fileName to $destPath"
    fi
done

echo "File Count: $fileCount"
