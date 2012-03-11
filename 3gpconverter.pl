#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Std;
use File::stat;
use File::Spec;
use File::Basename;
use Time::Piece;

my %patterns = (
  "%Y%m%d_%H%M%S" => qr/(\d{8}_\d{6})\.[^\/]+$/,
  "%Y-%m-%d_%H-%M-%S" => qr/(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_\d+\.[^\/]+$/
);

my $OUTPUT_ROOT = "/srv/media/video/family";
my $WORKDIR = "/tmp/3gpconverter";

my %opts;
getopts("f:o",\%opts) or &usage;

&usage unless $opts{f};
if (! -e $opts{f}) {
  print STDERR "$opts{f} doesn't exist\n";
  &usage;
}

my $absfile   = File::Spec->rel2abs($opts{f});
my $basename  = basename $absfile;

my $t = &get_datetime($absfile);
print "using datetime $t for $absfile\n";

my ($outpath,$outfile) = &get_outpath($t,"avi");

my $cdate =  $t->cdate;
my $rc;
$rc = system("mkdir -p $WORKDIR");
die "unable to make work directory $WORKDIR: $?\n" unless $rc == 0;

if (-e "$WORKDIR/$outfile") {
  system("rm $WORKDIR/$outfile");
}

if ($absfile =~ m/.*avi$/) {
  print "copying $absfile to $WORKDIR/$outfile\n";
  $rc = system("cp -p \"$absfile\" $WORKDIR/$outfile");
  die "unable to copy $absfile to $WORKDIR/$outfile: $?\n" unless $rc == 0;
} else {
  die "output file already exists: $outpath/$outfile\n" if (!$opts{o} && -e "$outpath/$outfile"); 

  print "converting $absfile to $WORKDIR/$outfile\n";
  $rc = system("ffmpeg -i \"$absfile\" -b 9000K -r 30 -ab 128K -f avi -vcodec libxvid -acodec libmp3lame \"$WORKDIR/$outfile\"");
  die "unable to convert $absfile: $?\n" unless $rc == 0;
}

print "moving $WORKDIR/$outfile to $outpath/$outfile\n";
$rc = system("mkdir -p $outpath");
die "unable to make output path $outpath: $?\n" unless $rc == 0;
$rc = system("mv \"$WORKDIR/$outfile\" $outpath/$outfile");
die "unable to move $WORKDIR/$outfile to $outpath/$outfile: $?\n" unless $rc == 0;
$rc = system("touch -d \"$cdate\" $outpath/$outfile");
die "unable to update creation time on $outpath/$outfile: $?\n" unless $rc == 0;

sub get_datetime {
  my $file = shift;
  my $t;
  for my $key (keys %patterns) {
    if ($file =~ $patterns{$key}) {
      eval {
        $t = Time::Piece->strptime($1,$key); 
      };
      last unless $@;
    }
    print "could not match date on $key: $file\n";
  }
  if (!$t) {
    print "all pattern matches failed, using timestamp: $file\n";
    $t = localtime(stat($file)->mtime);
  }
  return $t;
}

sub get_outpath {
  my $t   = shift;
  my $ext = shift;
  my $outpath = "$OUTPUT_ROOT/".$t->strftime("%Y/%m");
  my $outfile = $t->strftime("%Y%m%d_%H%M%S");
  $outfile .= ".$ext" if $ext;
  return ($outpath,$outfile);
}

sub usage {
  print STDERR "$0 -f <3gpfile>\n";
  exit -1;
}
