#!/usr/bin/perl

use File::Find;
use File::Spec;
use Digest::MD5 qw(md5_hex);
use Time::Piece;
use Getopt::Std;
use File::Glob ':glob';

my %opts = ();
getopts("sbcmd:",\%opts) or &usage;

my $count =  `ps -ef | grep -v grep | grep perl | grep -c $0`;
die "$0 is already running\n" if $count > 1;

my $home = glob("~");
my $root_outpath = "/srv/media/photos";
#my $root_outpath = "$home/Pictures/Family";

my @DATE_FIELDS = (
  "exif:DateTimeOriginal",
  "exif:DateTimeDigitized",
  "exif:DateTime",
  "MicrosoftPhoto:DateAcquired",
  "date:modify",
  "date:create"
);
my @dirs = split(/,/,$opts{d});

for my $dir (@dirs) {
  &usage("invalid directory: $dir") unless ($dir && -d $dir); 
  &check_for_changes($dir);
}

for my $dir (@dirs) {
  File::Find::find({wanted => \&wanted}, $dir);
}

sub wanted {
  if (/^.*\.((?:jpe?g)|(?:png))$/i) {
    my $ext = $1;
    $ext =~ s/jpeg/jpg/i;
    $ext = lc $ext;
    print "scanning file $File::Find::name\n";
    chomp(my @lines = `/usr/bin/identify -verbose \"$File::Find::name\" | grep -i date`);
    my %metadata = ();
    for my $line (@lines) {
      if ($line =~ m/^\s*([^\s]*):\s+(.*)$/) {
        my $key = $1;
        my $val = $2;
        #$val =~ s/-\d\d:\d\d$//;
        $val =~ s/Z$//;
        $val =~ s/-(\d\d):(\d\d)$/-$1$2/;
        $val =~ s/\+(\d\d):(\d\d)$/+$1$2/;
        $val =~ s/^(\d\d\d\d):(\d\d):(\d\d)\s+/$1-$2-$3T/;
#        if ($val !~ m/2005-01-01T00:00:0/) {
          $metadata{$key} = $val;
#        }
      }
    }
    my $t;
    for my $key (@DATE_FIELDS) {
      print "$key = $metadata{$key}\n";
      if ($metadata{$key}) {
        #if ($key =~ m/^exif/) {
        #  eval{ $t = Time::Piece->strptime($metadata{$key},"%Y:%m:%d%t%H:%M:%S"); };
        #  print STDERR "invalid date, $key=$metadata{$key}\n" if $@;
        #} else { 
          eval{ $t = Time::Piece->strptime($metadata{$key},"%Y-%m-%dT%H:%M:%S%z"); };
          if (!$t) {
            eval{ $t = Time::Piece->strptime($metadata{$key},"%Y-%m-%dT%H:%M:%S"); };     }
          print STDERR "invalid date, $key=$metadata{$key}\n" if $@;
        #}
        last if ($t);
      }
    }
    if ($t) {
      my $outpath = "$root_outpath/".$t->strftime("%Y/%m");
      my $outfile = $t->strftime("%Y%m%d_%H%M%S.$ext");
      print "$outpath/$outfile\n";
      if (-e "$outpath/$outfile" && $opts{s}) {
        print "file already exists: $outpath/$outfile\n";
      } else {
        my $has_duplicate = 0;
        if (-e "$outpath/$outfile") {
          if (&is_duplicate($File::Find::name,"$outpath/$outfile")) {
            print "duplicate file already exists: $outpath/$outfile\n";
            $has_duplicate = 1;
          } else {
            print "file already exists: $outpath/$outfile\n";
            my $count = 0;
            $outfile =~ s/\.$ext/_$count.$ext/;
            while (-e "$outpath/$outfile" and !$has_duplicate) {
              if (&is_duplicate($File::Find::name,"$outpath/$outfile")) {
                print "duplicate file already exists: $outpath/$outfile\n";
                $has_duplicate = 1;
              } else {
                print "file already exists: $outpath/$outfile\n";
                $count++;
                $outfile =~ s/_\d+\.$ext/_$count.$ext/;
              }
            }
          }
        }
        if ($has_duplicate && $opts{m}) {
          system("mkdir -p /tmp/photo_duplicates");
          system("mv \"$File::Find::name\" /tmp/photo_duplicates");
        } elsif (!$has_duplicate) {
          system("mkdir -p $outpath");
          if ($opts{c}) {
            print "copying $File::Find::name to $outpath/$outfile\n";
            system("cp -p \"$File::Find::name\" \"$outpath/$outfile\"");
            system("chmod a-x \"$outpath/$outfile\"");
            system("chgrp sambashare \"$outpath/$outfile\"");
          } elsif ($opts{m}) {
            print "moving $File::Find::name to $outpath/$outfile\n";
            system("mv \"$File::Find::name\" \"$outpath/$outfile\"");
            system("chmod a-x \"$outpath/$outfile\"");
            system("chgrp sambashare \"$outpath/$outfile\"");
          }
        }
      }
    } elsif ($opts{b}) {
      my $outpath = "$root_outpath/invalid";
      system("mkdir -p $outpath");
      system("cp -p \"$File::Find::name\" \"$outpath/$_\"");
      system("chmod a-x \"$outpath/$_\"");
      print "unable to convert file name: $File::Find::name\n";
    }
    else {
      print "unable to convert file name: $File::Find::name\n";
    }
  }
}

sub check_for_changes {
  my $directory = shift;
  my @files = bsd_glob("$directory/*");
  my $first = scalar(@files);
  sleep 15;
  @files = bsd_glob("$directory/*");
  my $second = scalar(@files);
  if ($first < $second) {
    print "$0: files are being added to $directory, try again later\n";
    exit -1; 
  }
}

sub is_duplicate {
  my $file1 = shift;
  my $file2 = shift;
  open(FILE1,"< $file1") or die "unable to open $file1\n";
  open(FILE2,"< $file2") or die "unable to open $file2\n";
  binmode(FILE1);
  binmode(FILE2);
  my $cs1 = md5_hex(<FILE1>);
  my $cs2 = md5_hex(<FILE2>);
  return $cs1 eq $cs2; 
}

sub usage {
  my $msg = shift;
  print "$msg\n" if $msg;
  print "$0 [-m] [-d <dir>] [-e <extension>]\n";
  exit -1;
}
