#!/usr/bin/perl

use File::Find;
use Time::Piece;
use File::stat;
use File::Spec;
use Getopt::Std;
use File::Glob ':glob';
use Image::ExifTool;
use Digest::MD5 qw(md5_hex);

my %patterns = (
  "%Y%m%d_%H%M%S" => qr/(\d{8}_\d{6})\.[^\/]+$/,
  "%Y-%m-%d_%H-%M-%S" => qr/(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_\d+\.[^\/]+$/,
  "%Y-%m-%d %H.%M.%S" => qr/(\d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.\d{2})\.[^\/]+$/
);

my %scanners = (
  "3gp" => \&scan_3gp,
  "mp4" => \&mov_scanner,
  "mov" => \&mov_scanner,
  "mod" => \&mod_scanner,
  "jpg" => \&photo_scanner,
  "jpeg" => \&photo_scanner,
  "png" => \&photo_scanner,
  "avi" => \&copy_scanner,
  "mpg" => \&copy_scanner
);

my @DATE_FIELDS = (
  "exif:DateTimeOriginal",
  "exif:DateTimeDigitized",
  "exif:DateTime",
  "MicrosoftPhoto:DateAcquired",
  "date:modify",
  "date:create"
);

my $WORKDIR = "/tmp/media_scanner";

my $exifTool = new Image::ExifTool;

my %opts = ();
getopts("sbcmd:o",\%opts) || &usage;
&usage unless $opts{d};

my $HOME_DIR  = glob("~");

my $VIDEO_OUTPUT_ROOT = "/video";
my $PHOTO_OUTPUT_ROOT = "/photo";

&check_already_running;

my $disk_usage = `df -h | grep srv | tr -s ' ' | cut -f5 -d' ' | sed 's/%//g'`;
die "$0 not enough freespace available: disk is $disk_usage% utilized\n" if $disk_usage > 90;

&check_directories(@dirs);

&create_workdir;

while(1) {
  my @dirs = split /,/,$opts{d};
  my $no_changes = &check_directories_for_changes(@dirs);
  if ($no_changes) {
    for my $dir (@dirs) {
      print "scanning for new files in $dir...\n";
      File::Find::find({wanted => \&wanted}, $dir);
    }
  }  
  sleep 60;
}

sub wanted {
  if (!-d $File::Find::name && /\.([^.]+)$/) {
    my $extension = lc($1);
    $scanners{$extension}->($File::Find::name,$extension) if $scanners{$extension};
  }
}

sub create_workdir {
  my $rc = system("mkdir -p $WORKDIR");
  die "unable to make work directory $WORKDIR: $?\n" unless $rc == 0;
}

sub scan_3gp {
  my $filename = shift;
  my $extension = shift;
  my $t = &get_datetime($filename);
  my ($outpath,$outfile) = &get_outpath($t,"avi");
  if ($opts{o} || ! -e "$outpath/$outfile") {
    print "new: $outpath/$outfile\n";
    system("rm \"$WORKDIR/$outfile\"");
    &convert_3gp($filename,"$WORKDIR/$outfile");
    &copy_file($t,"$WORKDIR/$outfile",$outpath,$outfile);
    system("rm \"$WORKDIR/$outfile\"");
    if ($opts{m}) {
      print "removing $filename\n";
      system("rm \"$filename\"");
    }
  } elsif ($opts{m}) {
    print "removing $filename due to existing file: $outpath/$outfile\n";
    system("rm \"$filename\"");
  } else {
    print "skipping existing file: $outpath/$outfile\n";
  }
}

sub mov_scanner {
  my $filename = shift;
  my $extension = shift;
  my $t = &get_datetime($filename);
  my ($outpath,$outfile) = &get_outpath($t,$extension);
  if ($opts{o} || ! -e "$outpath/$outfile") {
    print "new: $outpath/$outfile\n";
    my $rotated = &rotate_video($filename,$WORKDIR,$outfile);
    &copy_file($t,$rotated,$outpath,$outfile);
    if ($rotated ne $filename) {
      system("rm \"$rotated\"");
    }
    if ($opts{m}) {
      print "removing $filename\n";
      system("rm \"$filename\"");
    }
  } elsif ($opts{m}) {
    print "removing $filename due to existing file: $outpath/$outfile\n";
    system("rm \"$filename\"");
  } else {
    print "skipping existing file: $outpath/$outfile\n";
  }
}

sub mod_scanner {
  my $filename = shift;
  my $extension = shift;
  my $t = &get_datetime($filename);
  my ($outpath,$outfile) = &get_outpath($t,"mp4");
  if ($opts{o} || ! -e "$outpath/$outfile") {
    print "new: $outpath/$outfile\n";
    &convert_mod($filename,"$WORKDIR/$outfile");
    &copy_file($t,"$WORKDIR/$outfile",$outpath,$outfile);
    system("rm \"$WORKDIR/$outfile\"");
    if ($opts{m}) {
      print "removing $filename\n";
      system("rm \"$filename\"");
    }
  } elsif ($opts{m}) {
    print "removing $filename due to existing file: $outpath/$outfile\n";
    system("rm \"$filename\"");
  } else {
    print "skipping existing file: $outpath/$outfile\n";
  }
}

sub copy_scanner {
  my $filename = shift;
  my $extension = shift;
  my $t = &get_datetime($filename);
  my ($outpath,$outfile) = &get_outpath($t,$extension);
  if ($opts{o} || ! -e "$outpath/$outfile") {
    print "new: $outpath/$outfile\n";
    &copy_file($t,$filename,$outpath,$outfile);
    if ($opts{m}) {
      print "removing $filename\n";
      system("rm \"$filename\"");
    }
  } elsif ($opts{m}) {
    print "removing $filename due to existing file: $outpath/$outfile\n";
    system("rm \"$filename\"");
  } else {
    print "skipping existing file: $outpath/$outfile\n";
  }
}

sub copy_file {
  my $t      = shift;
  my $source = shift;
  my $target_path = shift;
  my $target = shift;

  my $cdate =  $t->cdate;
  print "moving $source to $target_path/$target\n";
  &make_path($target_path);
  my $rc = system("cp --preserve=timestamps \"$source\" \"$target_path/$target\"");
  system("chown nobody:nogroup \"$target_path/$target\"");
  die "unable to move $source to $target_path/$target: $?\n" unless $rc == 0;
  $rc = system("touch -d \"$cdate\" \"$target_path/$target\"");
  die "unable to update creation time on $target_path/$target: $?\n" unless $rc == 0;
}

sub convert_3gp {
  my $original  = shift;
  my $converted = shift;
  print "converting $original to $converted\n";
  $rc = system("ffmpeg -i \"$original\" -b 9000K -r 30 -ab 128K -f avi -vcodec libxvid -acodec libmp3lame \"$converted\"");
  die "unable to convert $original: $?\n" unless $rc == 0;
}

sub convert_mod {
  my $original = shift;
  my $converted = shift;

  print "converting $original to $converted\n";
  $rc = system("HandBrakeCLI -i \"$original\" -o \"$converted\" --preset=\"Normal\"");
  die "unable to convert $original: $?\n" unless $rc == 0;
}

sub rotate_video {
  my $original = shift;
  my $rotated_path = shift;
  my $rotated = shift;

  my $info = $exifTool->ImageInfo($original);

  my $degrees = $info->{Rotation};

  my $result = $original;

  if ($degrees) {
    my $rotate = $degrees / 90;

    my $current = $original;

    for my $x (1 .. $rotate) {
      print "rotating 90 degrees: $original\n";
      my $rc = system("avconv -i \"$current\" -vf \"transpose=1\" -crf 20 -preset slow -c:a copy \"$rotated_path/$x-$rotated\"");
      die "unable to rotate \"$current\" video: $?" unless $rc == 0;
      $current = "$rotated_path/$x-$rotated";
    }
    $result = $current;
  }
  return $result;
}

sub photo_scanner {
  my $filename = shift;
  my $ext = shift;
  $ext =~ s/jpeg/jpg/i;
  $ext = lc $ext;
  print "scanning file $filename\n";
  chomp(my @lines = `/usr/bin/identify -verbose \"$filename\" | grep -i date`);
  my %metadata = ();
  for my $line (@lines) {
    if ($line =~ m/^\s*([^\s]*):\s+(.*)$/) {
      my $key = $1;
      my $val = $2;
      $val =~ s/Z$//;
      $val =~ s/-(\d\d):(\d\d)$/-$1$2/;
      $val =~ s/\+(\d\d):(\d\d)$/+$1$2/;
      $val =~ s/^(\d\d\d\d):(\d\d):(\d\d)\s+/$1-$2-$3T/;
      $metadata{$key} = $val;
    }
  }
  my $t;
  for my $key (@DATE_FIELDS) {
    print "$key = $metadata{$key}\n";
    if ($metadata{$key}) {
        my $time_string = $metadata{$key};
        $time_string =~ s/[+-]\d\d\d\d$//;
        eval{ $t = Time::Piece->strptime($time_string,"%Y-%m-%dT%H:%M:%S%z");};
        if (!$t) {
          eval{ $t = Time::Piece->strptime($time_string,"%Y-%m-%dT%H:%M:%S");};
          print STDERR "invalid date, $key=$time_string\n" if $@;
        }
      last if ($t);
    }
  }
  if ($t) {
    my $outpath = "$PHOTO_OUTPUT_ROOT/".$t->strftime("%Y/%m");
    my $outfile = $t->strftime("%Y%m%d_%H%M%S.$ext");
    print "$outpath/$outfile\n";
    if (-e "$outpath/$outfile" && $opts{s}) {
      print "file already exists: $outpath/$outfile\n";
    } else {
      my $has_duplicate = 0;
      if (-e "$outpath/$outfile") {
        if (&is_duplicate($filename,"$outpath/$outfile")) {
          print "duplicate file already exists: $outpath/$outfile\n";
          $has_duplicate = 1;
        } else {
          print "file already exists: $outpath/$outfile\n";
          my $count = 0;
          $outfile =~ s/\.$ext/_$count.$ext/;
          while (-e "$outpath/$outfile" and !$has_duplicate) {
            if (&is_duplicate($filename,"$outpath/$outfile")) {
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
        system("mv \"$filename\" /tmp/photo_duplicates");
      } elsif (!$has_duplicate) {
        &make_path($outpath);
        if ($opts{c}) {
          print "copying $filename to $outpath/$outfile\n";
          system("cp --preserve=timestamps \"$filename\" \"$outpath/$outfile\"");
          system("chown nobody:nogroup \"$outpath/$outfile\"");
        } elsif ($opts{m}) {
          print "moving $filename to $outpath/$outfile\n";
          system("cp --preserve=timestamps \"$filename\" \"$outpath/$outfile\"");
          system("rm \"$filename\"");
          system("chown nobody:nogroup \"$outpath/$outfile\"");
        }
      }
    }
  } elsif ($opts{b}) {
    my $outpath = "$PHOTO_OUTPUT_ROOT/invalid";
    &make_path($outpath);
    system("cp --preserve=timestamps \"$filename\" \"$outpath/$_\"");
    system("chown nobody:nogroup \"$outpath/$_\"");
    print "unable to convert file name: $filename\n";
  }
  else {
    print "unable to convert file name: $filename\n";
  }
}

sub make_path {
  my $full_path = shift;
  my @pieces = split /\//, $full_path;
  shift @pieces;
  my $path = "";
  foreach (@pieces) {
    $path = "$path/$_"; 
    system("mkdir $path") unless -d $path;
  } 
}

sub check_already_running {
  my $count =  `ps -ef | grep -v grep | grep perl | grep -c $0`;
  die "$0 is already running\n" if $count > 1;
}

sub check_directories {
  for my $dir (@_) {
    &usage unless -d $dir;
  }
}

sub check_directories_for_changes {
  my $no_changes = 1;
  for my $dir (@_) {
    $no_changes = &check_for_changes($dir);
    last if !$no_changes;
  }
  return $no_changes;
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
    print "files are being added to $directory, waiting...\n";
    #exit -1;
    return 0;
  }
  return 1;
}

sub get_datetime {
  my $file = shift;
  my $t;
  eval {
    $t = localtime(stat($file)->mtime);
  };
  if (!$t or $@) {
    print "could not determine timestamp from modification time\n";
    print "attempting to match based on filename\n";
    for my $key (keys %patterns) {
      if ($file =~ $patterns{$key}) {
        eval {
          $t = Time::Piece->strptime($1,$key);
          $t += localtime->tzoffset;
        };
        last unless $@;
      }
      print "could not match date on $key: $file\n";
    }
  }
  return $t;
}

sub get_outpath {
  my $t   = shift;
  my $ext = shift;
  my $outpath = "$VIDEO_OUTPUT_ROOT/".$t->strftime("%Y/%m");
  my $outfile = $t->strftime("%Y%m%d_%H%M%S");
  $outfile .= ".$ext" if $ext;
  return ($outpath,$outfile);
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
  print "Usage: $0 -d <dirs>\n";
  exit -1;
}

