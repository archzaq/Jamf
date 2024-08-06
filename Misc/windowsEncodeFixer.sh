#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 8-1-24    ###
### Updated: 8-6-24    ###
### Version: 1.0       ###
##########################

user=$(whoami)
source_dir="/Users/$user/Documents/Converted Bitlocker Recovery Keys"

# Loop through each file in the source directory
find "$source_dir" -type f -print0 | while IFS= read -r -d '' file; do
    # Check if the file does not start with "BitLocker"
    if ! head -n 1 "$file" | grep -q '^BitLocker'; then
        # Replace the first word with "BitLocker" using sed and overwrite the original file
        sed -i '' '1s/^[^ ]* /BitLocker /' "$file"
        echo "Corrected file: $file"
    else
        echo "File already starts with BitLocker: $file"
    fi
done
