#!/usr/bin/perl

use File::Find;
use File::Spec;
use File::Path qw(mkpath);
use File::Copy;
use Digest::MD5 qw(md5_hex);
use Time::Piece;
use Getopt::Std;
use File::Glob ':glob';
use Image::ExifTool;

my %opts = ();
getopts("sbcmd:",\%opts) or &usage;
&usage unless ($opts{d} && -d $opts{d}); 

# not cross-platform 
my $count =  `ps -ef | grep -v grep | grep perl | grep -c $0`;
die "$0 is already running\n" if $count > 1;

&check_for_changes($opts{d});

my $home = glob("~");
my $root_outpath = "/srv/media/photos";
#my $root_outpath = "$home/Pictures/Family";

my $exif = new Image::ExifTool;

my @DATE_FIELDS = (
  "DateTimeOriginal",
  "CreateDate",
  "ModifyDate",
  "ModifyDate (1)",
  "FileModifyDate",
  "GPSDateStamp",
  "GPSDateTime",
  "ProfileDateTime",
  "SonyDateTime"
);

File::Find::find({wanted => \&wanted}, $opts{d});

sub wanted {
  if (/^.*\.((?:jpe?g)|(?:png))$/i) {
    my $ext = $1;
    $ext =~ s/jpeg/jpg/i;
    $ext = lc $ext;
    print "scanning file $File::Find::name\n";
    my $date = &get_date($File::Find::name);
    my $t;
    eval{ $t = Time::Piece->strptime($date,"%Y:%m:%d%t%H:%M:%S"); };
    if ($@) {
      eval{ $t = Time::Piece->strptime($date,"%Y-%m-%dT%H:%M:%S%z"); };
      print STDERR "invalid date, $date\n" if $@;
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
        if ($has_duplicate) {
          mkpath "/tmp/photo_duplicates";
          move($File::Find::name,"/tmp/photo_duplicates");
        } else {
          mkpath $outpath;
          if ($opts{c}) {
            print "copying $File::Find::name to $outpath/$outfile\n";
            copy($File::Find::name,"$outpath/$outfile");
            &fix_timestamp($t, "$outpath/$outfile");
            # not cross-platform
            system("chmod a-x \"$outpath/$outfile\"");
          } elsif ($opts{m}) {
            print "moving $File::Find::name to $outpath/$outfile\n";
            move($File::Find::name,"$outpath/$outfile");
            &fix_timestamp($t, "$outpath/$outfile");
            # not cross-platform
            system("chmod a-x \"$outpath/$outfile\"");
          }
        }
      }
    } elsif ($opts{b}) {
      my $outpath = "$root_outpath/invalid";
      mkpath $outpath;
      copy($File::Find::name,"$outpath/$_");
      &fix_timestamp($t, "$outpath/$_");
      # not cross-platform
      system("chmod a-x \"$outpath/$_\"");
      print "unable to convert file name: $File::Find::name\n";
    } else {
      print "unable to convert file name: $File::Find::name\n";
    }
  }
}

sub check_for_changes {
  my $directory = shift;
  my @files = bsd_glob("$directory/*");
  my $first = scalar(@files);
  sleep 5;
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
  close(FILE1);
  close(FILE2);
  return $cs1 eq $cs2; 
}

sub get_date {
  my $file = shift;
  print "$file\n";
  my $info = $exif->ImageInfo($file);
  my %dates = ();
  for my $key (grep {/date/i} keys %{$info}) {
    $dates{$key} = $info->{$key};
  }
  my $selected_date;
  for my $key (@DATE_FIELDS) {
    if (!$selected_date && $dates{$key}) {
      $selected_date = $key;
    }
  }
  if (!$selected_date) {
    my @fields = keys %dates;
    $selected_date = shift @fields;
  }
  return $dates{$selected_date};
}

sub fix_timestamp {
  my $t    = shift;
  my $file = shift;
  my $seconds = $t->epoch + $t->offset;
  utime $seconds, $seconds, $file;
}

sub usage {
  print "$0 [-s] [-c] [-m] [-b] [-d <dir>]\n";
  print "  -s       : skip existing files\n";
  print "  -c       : copy the file\n";
  print "  -m       : move the file\n";
  print "  -b       : backup invalid files\n";
  print "  -d <dir> : directory to scan\n";
  exit -1;
}
