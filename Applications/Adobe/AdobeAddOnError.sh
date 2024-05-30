#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

if [ -d /Users/$USER/Library/Group\ Containers/UBF8T346G9.Office/User\ Content.localized/Startup.localized/ ]; then
    filePath="/Users/$USER/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized"

    cd "$filePath/Word/"
    rm -rf linkCreation.dotm SaveAsAdobePDF.ppam SaveAsAdobePDF.xlam        

    cd "$filePath/Excel/"
    rm -rf linkCreation.dotm SaveAsAdobePDF.ppam SaveAsAdobePDF.xlam

    cd "$filePath/PowerPoint/"
    rm -rf linkCreation.dotm SaveAsAdobePDF.ppam SaveAsAdobePDF.xlam

fi