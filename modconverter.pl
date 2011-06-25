#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Std;
use File::stat;
use File::Spec;
use Time::Piece;

my %opts;
getopts("f:o",\%opts) or &usage;

&usage unless $opts{f};
if (! -e $opts{f}) {
  print STDERR "$opts{f} doesn't exist\n";
  &usage;
}

my $infile  = File::Spec->rel2abs($opts{f});
my $t;
if ($infile =~ m/^\/?(?:[^\/]*\/)*(\d{8}_\d{6})(?:\.[^\/]*)*$/) {
  eval{
    $t = Time::Piece->strptime($1,"%Y%m%d_%H%M%S"); 
  };
  if ($@) {
    print STDERR "not a valid date, using timestamp instead: $1\n";
  } 
}
$t = localtime(stat($opts{f})->mtime) unless $t;
my $outpath = glob("~")."/Videos/Family/".$t->strftime("%Y/%m");
my $outfile = $t->strftime("%Y%m%d_%H%M%S.avi");
my $workdir = "/tmp/modconverter";

my $datetime =  $t->datetime;
my $cdate =  $t->cdate;
my $rc;
$rc = system("mkdir -p $workdir");
die "unable to make work directory $workdir: $?\n" unless $rc == 0;

if ($infile =~ m/.*avi$/) {
  print "copying $infile to $workdir/$outfile\n";
  $rc = system("cp -p \"$infile\" $workdir/$outfile");
  die "unable to copy $infile to $workdir/$outfile: $?\n" unless $rc == 0;
} else {
  die "output file already exists: $outpath/$outfile\n" if (!$opts{o} && -e "$outpath/$outfile"); 
  my $cfgdir = glob("~/.transcode");
  if (-e $cfgdir) {
    chdir $cfgdir;
  }
  print "transcoding $infile to $workdir/$outfile\n";
  $rc = system("transcode -i \"$infile\" -y xvid4,tcaud --export_par 5 --export_asr 3 -o \"$workdir/$outfile\"");
  die "unable to transcode $infile: $?\n" unless $rc == 0;
}

#system("/usr/bin/AtomicParsley \"$name.avi\" -y \"$datetime\" -o $name.tagged.avi");

print "moving $workdir/$outfile to $outpath/$outfile\n";
$rc = system("mkdir -p $outpath");
die "unable to make output path $outpath: $?\n" unless $rc == 0;
$rc = system("mv \"$workdir/$outfile\" $outpath/$outfile");
die "unable to move $workdir/$outfile to $outpath/$outfile: $?\n" unless $rc == 0;
$rc = system("touch -d \"$cdate\" $outpath/$outfile");
die "unable to update creation time on $outpath/$outfile: $?\n" unless $rc == 0;

sub usage {
  print STDERR "$0 -f <modfile>\n";
  exit -1;
}
