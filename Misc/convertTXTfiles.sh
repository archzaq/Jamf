#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 8-1-24    ###
### Updated: 8-6-24    ###
### Version: 1.0       ###
##########################

user=$(whoami)
source_dir="/Users/$user/Documents/Bitlocker Recovery Keys"
destination_dir="/Users/$user/Documents/Converted Bitlocker Recovery Keys"

# Find all .TXT files recursively in source_dir and iterate over them
find "$source_dir" -type f -name '*.TXT' | while IFS= read -r file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        
        iconv -f windows-1252 -t utf-8 "$file" > "$destination_dir/$filename"
        
        echo "Converted $file to UTF-8 and saved as $destination_dir/$filename"
    fi
done
