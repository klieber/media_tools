#!/usr/bin/perl

use File::Find;
use Time::Piece;
use File::stat;
use File::Spec;

my $MOUNT_DIR = "/media/EVERIO_HDD/SD_VIDEO";
my $HOME_DIR  = glob("~");
my $LOCAL_DIR = "$HOME_DIR/Videos/Family";
my $REMOTE_USER   = "klieber";
my $REMOTE_SERVER = "kyle-desktop";
my $REMOTE_DIR    = "/var/shared/media/video";
my $MODCONVERTER  = "$HOME_DIR/bin/modconverter.pl";

my $count =  `ps -ef | grep -v grep | grep perl | grep -c $0`;
my $connected = system("ssh $REMOTE_SERVER hostname >/dev/null 2>&1") == 0;
if (-d $MOUNT_DIR && $count <= 1 && $connected) {
  print "scanning for new mod files...\n";
  File::Find::find({wanted => \&wanted}, $MOUNT_DIR);
  
  print "syncing with $REMOTE_SERVER...\n";
  system("rsync -a -vv -e ssh $LOCAL_DIR $REMOTE_USER\@$REMOTE_SERVER:$REMOTE_DIR");
}

sub wanted {
  if (!-d $File::Find::name && /\.MOD/i) {
    my $t = localtime(stat($File::Find::name)->mtime);
    my $outpath = "$LOCAL_DIR/".$t->strftime("%Y/%m");
    my $outfile = $t->strftime("%Y%m%d_%H%M%S.avi");
    if (! -e "$outpath/$outfile") {
      my $rc = system("ssh $REMOTE_SERVER ls $outpath/$outfile >/dev/null 2>&1");
      if ($rc != 0) {
        print "new: $outpath/$outfile\n";
        system("$MODCONVERTER -f $File::Find::name");
      } else {
        #print "remote existing file: $outpath/$outfile\n";
      }
    } else {
      #print "local existing file: $outpath/$outfile\n";
    } 
  }
}
