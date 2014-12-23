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

level="0.8"
if [ "$2" ]; then
  level=$2
fi

if [ ! -e $probe ]; then
  echo Creating probe file: $probe
  ffprobe -show_frames -of compact=p=0 -f lavfi "movie=$file,select=gt(scene\,$level)" > $probe
  [ $? = 0 ] || ( echo "Unable to create probe file. Aborting." && exit 3 )
fi

start=0
clip=1

mkdir -p $filepath/$name

for end in $(cat $probe | cut -f4 -d'|' | cut -f2 -d=); do
  clip_string=$(printf "%.4d\n" $clip)
  echo Creating clip $clip at $filepath/$name/${name}_${clip_string}.$ext
  ffmpeg -i $file -ss $start -to $end -async 1 $name/${name}_${clip_string}.$ext
  [ $? = 0 ] || echo "Failure creating clip $clip."
  start=$end
  ((clip++))
done
clip_string=$(printf "%.4d\n" $clip)
ffmpeg -i $file -ss $start -async 1 $name/${name}_${clip_string}.$ext
