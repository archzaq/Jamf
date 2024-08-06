#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 8-1-24    ###
### Updated: 8-6-24    ###
### Version: 1.0       ###
##########################

count=0
user=$(whoami)
filePath="/Users/$user/Documents/AllNoelBitLocker"
outputCSV="/Users/$user/Documents/bitlockerKeyTDriveExport2.csv"

echo "File Name,Identifier,Recovery Key ID" > "$outputCSV"

find "$filePath" -type f -name '*.*' | while IFS= read -r file;
do
    fileName=$(basename "$file")
    identifier=''
    keyID=''

    while IFS= read -r line;
    do
        line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        numHyphens=$(echo "$line" | grep -o '-' | wc -l)

        if [[ "$numHyphens" -eq 4 ]];
        then
            identifier=$(echo "$line" | awk -F ': ' '{print ($1 == "Full recovery key identification") ? $2 : $1}')
        fi

        if [[ "$numHyphens" -eq 7 ]];
        then
            keyID="$line"
        fi

    done < "$file"

    if [[ -n "$identifier" && -n "$keyID" ]];
    then
        printf '"%s","%s","%s"\n' "$fileName" "$identifier" "$keyID" >> "$outputCSV"
        identifier=''
        keyID=''
        ((count++))
    fi
done

echo "Export Count: $count"

