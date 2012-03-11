#!/usr/bin/perl

use File::Find;
use Time::Piece;
use File::stat;
use File::Spec;
use Getopt::Std;
use File::Glob ':glob';

my %patterns = (
  "%Y%m%d_%H%M%S" => qr/(\d{8}_\d{6})\.[^\/]+$/,
  "%Y-%m-%d_%H-%M-%S" => qr/(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_\d+\.[^\/]+$/
);

my %opts = ();
getopts("d:",\%opts) || &usage;
&usage unless $opts{d};

my $HOME_DIR  = glob("~");
my $CONVERTER  = "$HOME_DIR/bin/3gpconverter.pl";
my $OUTPUT_ROOT = "/srv/media/video/family";

my $count =  `ps -ef | grep -v grep | grep perl | grep -c $0`;
die "$0 is already running\n" if $count > 1;

my @dirs = split /,/,$opts{d};
for my $dir (@dirs) {
  &usage unless -d $dir;
  &check_for_changes($dir);
}
for my $dir (@dirs) {
  print "scanning for new 3gp files in $dir...\n";
  File::Find::find({wanted => \&wanted}, $dir);
}

sub wanted {
  if (!-d $File::Find::name && /\.3gp/i) {
    my $t = &get_datetime($File::Find::name);
    my ($outpath,$outfile) = &get_outpath($t,"avi");
    if (! -e "$outpath/$outfile") {
      print "new: $outpath/$outfile\n";
      system("$CONVERTER -f \"$File::Find::name\"");
    } else {
     print "existing file: $outpath/$outfile\n";
    }
  }
}

sub check_for_changes {
  my $directory = shift;
  print "watching $directory for changes\n";
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
  print "Usage: $0 -d <dirs>\n";
  exit -1;
}
