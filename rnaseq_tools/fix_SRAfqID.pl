#!/usr/bin/perl
use strict; 
use warnings; 

-t and !@ARGV and die "perl $0 down_SRR_R2.fq > down_SRR_R2.fix.fq\n"; 

while (my $l1 = <>) {
  my $l2 = <>; 
  my $l3 = <>; 
  my $l4 = <>; 
  if ($l1 =~ s!^\@\S+\.([12])\s+([^:]+:\d+:[^:]+(:\d+){4})(?:\s+.+|\s*)$!\@$2 $1!) {
  } elsif ($l1 =~ s!^\@(\S+)\.([12])(?:\s*|\s+length=\d+\s*)$!\@$1 $2!) {
  }
  $l3 =~ s!^\+.*$!+!; 
  print "$l1$l2$l3$l4"; 
}
