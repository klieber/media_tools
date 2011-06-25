#!/usr/bin/perl

use File::Find;
use Time::Piece;
use File::stat;
use File::Spec;

my $MOUNT_DIR = "/media/EVERIO_HDD/SD_VIDEO";
my $HOME_DIR = glob("~");

my $count =  `ps -ef | grep -v grep | grep perl | grep -c $0`;
my $connected = system("ssh kyle-desktop hostname >/dev/null 2>&1") == 0;
if (-d $MOUNT_DIR && $count <= 1 && $connected) {
  print "scanning for new mod files...\n";
  File::Find::find({wanted => \&wanted}, $MOUNT_DIR);
  
  print "syncing with kyle-desktop...\n";
  system("rsync -a -vv -e ssh /home/klieber/Videos/Family klieber\@kyle-desktop:/var/shared/media/video");
}

sub wanted {
  if (!-d $File::Find::name && /\.MOD/i) {
    my $t = localtime(stat($File::Find::name)->mtime);
    my $outpath = "$HOME_DIR/Videos/Family/".$t->strftime("%Y/%m");
    my $outfile = $t->strftime("%Y%m%d_%H%M%S.avi");
    if (! -e "$outpath/$outfile") {
      my $rc = system("ssh kyle-desktop ls $outpath/$outfile >/dev/null 2>&1");
      if ($rc != 0) {
        print "new: $outpath/$outfile\n";
        system("$HOME_DIR/bin/modconverter.pl -f $File::Find::name");
      } else {
        #print "remote ext file: $outpath/$outfile\n";
      }
    } else {
      #print "local ext file: $outpath/$outfile\n";
    } 
  }
}
