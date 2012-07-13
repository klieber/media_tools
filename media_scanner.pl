#!/usr/bin/perl

use File::Find;
use Time::Piece;
use File::stat;
use File::Spec;
use Getopt::Std;
use File::Glob ':glob';
use Image::ExifTool;

my %patterns = (
  "%Y%m%d_%H%M%S" => qr/(\d{8}_\d{6})\.[^\/]+$/,
  "%Y-%m-%d_%H-%M-%S" => qr/(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_\d+\.[^\/]+$/,
  "%Y-%m-%d %H.%M.%S" => qr/(\d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.\d{2})\.[^\/]+$/
);

my %scanners = (
  "3gp" => \&scan_3gp,
  "mp4" => \&copy_scanner,
  "mov" => \&mov_scanner
);

my $WORKDIR = "/tmp/media_scanner";

my $exifTool = new Image::ExifTool;

my %opts = ();
getopts("md:o",\%opts) || &usage;
&usage unless $opts{d};

my $HOME_DIR  = glob("~");

my $OUTPUT_ROOT = "/srv/media/video/family";

&check_already_running;

&check_directories;

&create_workdir;

sub wanted {
  # check if this is a file
  # check if this is a supported file
  # get the name of the new file
  # if the new file doesn't exist or overwrite is true
  #   perform any conversion that is neccessary
  #   copy the converted file to the new file
  #   remove the converted file
  # if move is true
  #   remove the original file
  if (!-d $File::Find::name && /\.([^.])$/) {
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
    &rotate_video($filename,"$WORKDIR/$outfile");
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
  print "moving $source to $target_path/$target";
  my $rc = system("mkdir -p \"$target_path\"");
  die "unable to make output path $target_path: $?\n" unless $rc == 0;
  $rc = system("cp -p \"$source\" \"$target_path/$target\"");
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

sub rotate_video {
  my $original = shift;
  my $rotated_path = shift;
  my $rotated = shift;
  
  my $info = $exifTool->ImageInfo($file);

  my $degrees = $exifTool->{Rotation};

  if ($degrees) {
    my $rotate = $degrees / 90;

    my $current = $original;
  
    for my $x (1 .. $rotate) {
      my $rc = system("avconv -i \"$current\" -vf \"transpose=1\" -c:a copy -same_quant \"$rotated_path/$rotated.$x\"");
      die "unable to rotate \"$current\" video: $?" unless $rc == 0;
      $current = "$rotated_path/$rotated.$x";
    }
  }
}

sub check_already_running {
  my $count =  `ps -ef | grep -v grep | grep perl | grep -c $0`;
  die "$0 is already running\n" if $count > 1;
}

sub check_directories {
  for my $dir (@_) {
    &usage unless -d $dir;
    &check_for_changes($dir);
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
