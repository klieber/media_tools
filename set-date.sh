#!/bin/sh
file=$1
date=$2
exiftool -overwrite_original -P -DateTimeOriginal="$date" -CreateDate="$date" -ModifyDate="$date" $file
touch --time access  -d "$date" $file
touch -d "$date" $file
