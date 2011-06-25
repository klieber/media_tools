#!/usr/bin/perl

use File::Find;
use File::Spec;
use Digest::MD5 qw(md5_hex);
use Time::Piece;
use Getopt::Std;

my %opts = ();
getopts("md:e:",\%opts) or &usage;
&usage unless ($opts{d} && -d $opts{d}); 

my $home = glob("~");

my @DATE_FIELDS = (
  "exif:DateTimeOriginal",
  "exif:DateTimeDigitized",
  "exif:DateTime",
  "date:modify",
  "date:create"
);

File::Find::find({wanted => \&wanted}, $opts{d});

sub wanted {
  if (/^.*\.jpe?g$/i) {
    print "scanning file $File::Find::name\n";
    chomp(my @lines = `/usr/bin/identify -verbose \"$File::Find::name\" | grep -i date`);
    my %metadata = ();
    for my $line (@lines) {
      if ($line =~ m/^\s*([^\s]*):\s+(.*)$/) {
        my $key = $1;
        my $val = $2;
        $val =~ s/(-\d\d):(\d\d)$/$1$2/;
        $metadata{$key} = $val;
      }
    }
    my $t;
    for my $key (@DATE_FIELDS) {
      if ($metadata{$key}) {
        if ($key =~ m/^exif/) {
          eval{ $t = Time::Piece->strptime($metadata{$key},"%Y:%m:%d%t%H:%M:%S"); };
          print STDERR "invalid date, $key=$metadata{$key}\n" if $@;
        } else { 
          eval{ $t = Time::Piece->strptime($metadata{$key},"%Y-%m-%dT%H:%M:%S%z"); };
          print STDERR "invalid date, $key=$metadata{$key}\n" if $@;
        }
        last if ($t);
      }
    }
    if ($t) {
      my $outpath = "$home/Pictures/Family/".$t->strftime("%Y/%m");
      my $outfile = $t->strftime("%Y%m%d_%H%M%S.jpg");
      print "copying $File::Find::name to $outpath/$outfile\n";
      system("mkdir -p $outpath");
      system("cp -p \"$File::Find::name\" \"$outpath/$outfile\"");
    }
    else {
      my $outpath = "$home/Pictures/invalid";
      system("mkdir -p $outpath");
      system("cp -p \"$File::Find::name\" \"$outpath/$_\"");
      print "unable to convert file name: $File::Find::name\n";
    }
  }
}

sub usage {
  print "$0 [-m] [-d <dir>] [-e <extension>]\n";
  exit -1;
}
