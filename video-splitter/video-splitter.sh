#!/bin/bash

if [ ! $1 ]; then
  echo "Please provide a video file."
  exit 1
fi

file=$(basename $1)
name=$(echo $file | sed 's/\.[^.]*$//g')
ext=$(echo $file | sed 's/^.*\.\([^.]*\)$/\1/g')
filepath=$(dirname $(readlink -f $1))

probe="$name.probe"

cd $filepath

if [ ! -e $file ]; then
  echo "The file does not exist: $file"
  exit 2
fi

if [ ! -e $probe ]; then
  echo Creating probe file: $probe
  ffprobe -show_frames -of compact=p=0 -f lavfi "movie=$file,select=gt(scene\,.4)" > $probe
fi

start=0
clip=1

mkdir -p $filepath/$name

for end in $(cat $probe | cut -f4 -d'|' | cut -f2 -d=); do
  echo creating clip $clip at $filepath/$name/${name}_${clip}.$ext
  ffmpeg -i $file -ss $start -to $end -async 1 $name/${name}_${clip}.$ext
  start=$end
  ((clip++))
done
