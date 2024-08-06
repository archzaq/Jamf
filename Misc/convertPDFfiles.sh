#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 8-1-24    ###
### Updated: 8-6-24    ###
### Version: 1.0       ###
##########################

user=$(whoami)
source_dir="/Users/$user/Documents/NoelBitLocker"
destination_dir="/Users/$user/Documents/AllNoelBitLocker"

count=0
# Loop through each PDF file in the source directory
for file in "$source_dir"/*.pdf; do
    if [ -f "$file" ]; then
        filename=$(basename "$file" .pdf)
        
        pdftotext "$file" "$destination_dir/$filename.txt"
        
        echo "Extracted text from $file and saved as $destination_dir/$filename.txt"
        ((count++))
    fi
done

echo "Count: $count"
