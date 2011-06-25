#!/usr/bin/perl

use File::Find;
use File::Spec;
use Digest::MD5 qw(md5_hex);
use Time::Piece;
use Getopt::Std;

my %opts = ();
getopts("md:e:",\%opts) or &usage;
&usage unless ($opts{d} && -d $opts{d});

my %checksums = ();

File::Find::find({wanted => \&wanted}, $opts{d});

my $backup = "/tmp/backup/";
system("mkdir -p $backup");

for my $sum (keys %checksums) {
  my @files = sort @{$checksums{$sum}};
  if (scalar(@files) > 1) {
    my $preserve = shift @files;
    print "duplicate files with checksum: $sum\n";
    print "  preserving file: $preserve\n";
    for my $file (sort @files) {
      print "  deleting duplicate: $file\n";
      system("mv $file $backup") if $opts{m};
    }
  }
}

sub wanted {
  if (!-d $File::Find::name && (!$opts{e} || /^.*\.$opts{e}\z/si)) {
    print "scanning file $File::Find::name,";
    open(FILE,"< $File::Find::name") or die "unable to open $File::Find::name\n";
    binmode(FILE);
    my $cs = md5_hex(<FILE>);
    print $cs,"\n";
    $checksums{$cs} = [] unless $checksums{$cs};
    push @{$checksums{$cs}}, $File::Find::name;
    close(FILE);
  }
}

sub usage {
  print "$0 [-m] [-d <dir>] [-e <extension>]\n";
  exit -1;
}
