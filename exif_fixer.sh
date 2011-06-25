#!/bin/sh
file=$1
date=$(exiftool -FileModifyDate $file | cut -f2- -d: | sed 's/^ *//')
echo "$file, setting date to $date"
exiftool -overwrite_original -P -DateTimeOriginal="$date" -CreateDate="$date" $file
