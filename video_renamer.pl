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
  "Media Create Date",
  "Media Modify Date",
  "Track Create Date",
  "Track Modify Date",
  "Create Date",
  "Modify Date",
  "File Modification Date/Time"
);

File::Find::find({wanted => \&wanted}, $opts{d});

sub wanted {
  if (/^.*\.3gp$/i) {
    print "scanning file $File::Find::name\n";
    chomp(my @lines = `/usr/local/bin/exiftool \"$File::Find::name\" | grep -i date`);
    my %metadata = ();
    for my $line (@lines) {
      my ($key,@temp) = split(/:/,$line);
      my $val = join ":",@temp; 
      $key =~ s/^\s*//g;
      $key =~ s/\s*$//g;
      $val =~ s/^\s*//g;
      $val =~ s/\s*$//g;
      $val =~ s/(-\d\d):(\d\d)$/$1$2/;
      $metadata{$key} = $val;
    }
    my $t;
    for my $key (@DATE_FIELDS) {
      if ($metadata{$key}) {
        eval{ $t = Time::Piece->strptime($metadata{$key},"%Y:%m:%d%t%H:%M:%S"); };
        print STDERR "invalid date, $key=$metadata{$key}\n" if $@;
        if ($@) { 
          eval{ $t = Time::Piece->strptime($metadata{$key},"%Y-%m-%dT%H:%M:%S%z"); };
          print STDERR "invalid date, $key=$metadata{$key}\n" if $@;
        }
        last if ($t);
      }
    }
    if ($t) {
      my $outpath = "$home/Videos/Family/".$t->strftime("%Y/%m");
      my $outfile = $t->strftime("%Y%m%d_%H%M%S.3gp");
      print "copying $File::Find::name to $outpath/$outfile\n";
      system("mkdir -p $outpath");
      system("cp -p \"$File::Find::name\" \"$outpath/$outfile\"");
      my $cdate = $t->cdate;
      system("touch -d \"$cdate\" \"$outpath/$outfile\"");
    }
    else {
      my $outpath = "$home/Videos/invalid";
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
