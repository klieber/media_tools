#!/usr/bin/perl

use Getopt::Std;

my %opts = ();
getopts("o:",\%opts) or &usage;
&usage unless $opts{o} && -d $opts{o};
my $count =  `ps -ef | grep -v grep | grep perl | grep -c $0`;
die "$0 is already running\n" if $count > 1;

for my $file (@ARGV) {
  my $newfile = $file;
  $newfile =~ s/^.*\/([^\/]+)$/$1/;
  &crop_image($file, "$opts{o}/$newfile");

  my $date = &get_date($file);
  system("exiftool -overwrite_original -P -DateTimeOriginal=\"$date\" -CreateDate=\"$date\" \"$opts{o}/$newfile\"");
}

sub get_date {
  my $file = shift;
  chomp(my $date = `exiftool -FileModifyDate $file | cut -f2- -d: | sed 's/^ *//'`);
  return $date; 
}

sub get_size {
  my $file = shift;
  chomp(my $size = `exiftool -ImageSize $file | cut -f2- -d: | sed 's/^ *//'`);
  return $size; 
}

sub crop_image {
  my $file = shift;
  my $newfile = shift;
  my $size = &get_size($file); 
  my $newsize = $size;
  $newsize =~ s/655/618/;
  $newsize =~ s/841/804/;
  print "cropping $file ($size) to $newfile ($newsize)\n";
  system("convert -crop $newsize+0+0 $file $newfile");
}

sub usage {
  my $msg = shift;
  print "$msg\n" if $msg;
  print "$0 -o <output-directory> input-files\n";
  exit -1;
}
