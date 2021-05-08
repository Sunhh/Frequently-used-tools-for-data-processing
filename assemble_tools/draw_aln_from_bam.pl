#!/usr/bin/perl -w 
# SVG color names: http://www.december.com/html/spec/colorsvg.html
# 2015-04-22 Check 'XT:A:U/R/M' of left read to decide read pair's mapping is unique (orange) or repeat (lightgreen). 
use strict; 
use LogInforSunhh; 
use fileSunhh; 
use mathSunhh; 
use SeqAlnSunhh; 
my $ms = mathSunhh->new(); 
use SVG; 
use Getopt::Long; 
my %opts; 
GetOptions(\%opts, 
	"help!", 
	"bam:s",   # required
	"scfID:s", # required 
	"outSvg:s", # out.svg 
	"scfS:i",  # default 1
	"scfE:i",  # required if -scfS 
	"bp_per_point:f", # default 100
	"width_per_line:i", # default 1000 
	"bp_overlap:i", # default 30000 
	"tickStep:f", # default 10000 
	"tickUnit:s", # default k 
	"gapLis:s",   # N gap list. 
	"tagLis:s",   # Some other list for viewing. 
	"limit_short:i", # -1 
	"limit_long:i", # -1 
	"color_scheme:s", # 'backbone=black:add_blks=red:readpair_repeat=lightgreen:readpair_short=blue:readpair_long=red:readpair=orange'
); 

sub usage {
	print <<HH; 
################################################################################
# perl $0 -bam in.srt.bam -scfID scfID 
# 
# -bam            [] Required. input sorted bam file. 
# -scfID          [] Required. 
# -outSvg         [] Output svg text to this file instead of stdout if given. 
# -scfS           [1] 
# -scfE           [] End of scaffold
# -bp_per_point   [100] bps number each point in figure standing for. 
# -width_per_line [1000] Figure width per line. 
# -bp_overlap     [20e3]
# -tickStep       [10000]
# -tickUnit       [k] k/m/''
#
# -limit_short    [-1]
# -limit_long     [-1]
#
# -color_scheme   [''] Default is 'backbone=black:add_blks=red:readpair_repeat=lightgreen:readpair_short=blue:readpair_long=red:readpair=orange'; 
#
# -gapLis         [] NSP306_Pla01s04GC_Gt5h.scf.fa.Nlis 
#
# -tagLis         [] NSP306_Pla01s04GC_Gt5h.scf.fa.pattern_lis
################################################################################
HH
	exit 1; 
}
$opts{'help'} and &usage(); 
( defined $opts{'bam'} and defined $opts{'scfID'} ) or &usage(); 

$opts{'scfS'} //= 1; 
$opts{'bp_per_point'} //= 100; 
$opts{'width_per_line'} //= 1000; 
$opts{'bp_overlap'} //= 20e3; 
$opts{'tickStep'} //= 10000; 
$opts{'tickUnit'} //= 'k'; 
my $unit_len = 1000; 
$opts{'tickUnit'} eq '' and $unit_len = 1; 
$opts{'tickUnit'} eq 'k' and $unit_len = 1e3; 
$opts{'tickUnit'} eq 'm' and $unit_len = 1e6; 
$opts{'limit_short'} //= -1; 
$opts{'limit_long'} //= -1; 

my %color; 
$color{'backbone'} = 'black'; 
$color{'add_blks'} = 'red'; 
$color{'tag_blks'} = 'blue'; 
$color{'readpair_repeat'} = 'lightgreen'; 
$color{'readpair_short'} = 'blue'; 
$color{'readpair_long'} = 'red'; 
$color{'readpair'} = 'orange'; 
if ( defined $opts{'color_scheme'} and $opts{'color_scheme'} ne '' ) {
	for my $form (split(/:/, $opts{'color_scheme'})) {
		$form =~ m/^([^=\s]+)=([^\s=]+)$/ or &tsmsg("[Wrn] Skip bad color_scheme [$form]\n"); 
		$color{$1} = $2; 
		&tsmsg("[Msg] Setting color [$form]\n"); 
	}
}

my $outFh = \*STDOUT; 
defined $opts{'outSvg'} and $outFh = &openFH($opts{'outSvg'}, '>'); 


my @add_blks; 
if (defined $opts{'gapLis'}) {
	open G,'<',"$opts{'gapLis'}" or die; 
	while (<G>) {
		chomp; 
		my @ta = split(/\t/, $_); 
		my ($id, $s, $e) = @ta[0, 2, 3]; 
		$id eq $opts{'scfID'} or next; 
		$s > $e and ($s, $e) = ($e, $s); 
		push(@add_blks, [$s, $e]); 
	}
	close G; 
}

my @tag_blks; 
if (defined $opts{'tagLis'}) {
	open G,'<',"$opts{'tagLis'}" or die; 
	while (<G>) {
		chomp; 
		my @ta = split(/\t/, $_); 
		my ($id, $s, $e) = @ta[0, 2, 3]; 
		$id eq $opts{'scfID'} or next; 
		$s > $e and ($s, $e) = ($e, $s); 
		push(@tag_blks, [$s, $e]); 
	}
	close G; 
}


# Read infor from bam file. 
-e "$opts{'bam'}.bai" or &exeCmd_1cmd("samtools index $opts{'bam'}"); 
my @pair_se; 
{
my (%flag_hDiffF, %flag_hDiffR); 
%flag_hDiffF = %{ &SeqAlnSunhh::mk_flag( 'keep'=>'0=1,2=0,3=0,4=0,5=1' , 'drop'=>'' ) }; 
%flag_hDiffR = %{ &SeqAlnSunhh::mk_flag( 'keep'=>'0=1,2=0,3=0,4=1,5=0' , 'drop'=>'' ) }; 
my %should_ignoreRd; 
my $loc = ( defined $opts{'scfE'} ) ? "'$opts{'scfID'}':$opts{'scfS'}-$opts{'scfE'}" : "'$opts{'scfID'}'" ; 
# open F, '-|',"samtools view $opts{'bam'} $loc | sam_filter.pl -h2diff_F " or die; 
open F, '-|',"samtools view $opts{'bam'} $loc " or die; 
while (<F>) {
	chomp; 
	my @ta = split(/\t/, $_); 
	my $flag = $ta[1]; 
	my $rdID = $ta[0]; 
	defined $flag_hDiffF{$flag} or defined $flag_hDiffR{$flag} or next; 
	defined $should_ignoreRd{$rdID} or do { &SeqAlnSunhh::not_uniqBest( \@ta ) == 1 and $should_ignoreRd{ $rdID } = 1; }; 
	$flag_hDiffF{$flag} or next; 
	my ($id1, $pos1, $id2, $pos2, $ins_len) = @ta[2,3,6,7,8]; 
	my $xt_u = 1; 
	# $_ =~ m/\tXT:A:[RM](\t|$)/ and $xt_u = 0; 
	$id2 eq '=' or next; 
	my $pos3 = $pos1+$ins_len-1; 
	$pos1 <= $pos3 or next; # Skip PE pairs. 
	$pos1 >= $opts{'scfS'} or next; 
	defined $opts{'scfE'} and $pos3 > $opts{'scfE'} and next; 
	push(@pair_se, [$pos1, $pos3, $xt_u, $rdID]); 
}
close F; 
@pair_se = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @pair_se; 
for my $ar0 (@pair_se) {
	defined $should_ignoreRd{ $ar0->[3] } and $ar0->[2] = 0; 
}
if ( !(defined $opts{'scfE'}) ) {
	open H,'-|',"samtools view -H $opts{'bam'}" or die; 
	while (<H>) {
		chomp; 
		m/^\@SQ\tSN:(\S+)\tLN:(\d+)$/ or next; 
		$1 eq $opts{'scfID'} and $opts{'scfE'} = $2; 
		defined $opts{'scfE'} and last; 
	}
	close H; 
}
# $opts{'scfE'} //= $pair_se[-1][1]; 
}

# For svg: 
# Basic parameters 
my $base_y = 10; 
my $base_x = 100; 
my $step_y = 100; 
my $rdHeight_y = $step_y * 2/3; 
my $bp_per_line = int( $opts{'width_per_line'} * $opts{'bp_per_point'} ); 
&tsmsg("[Rec] bp_per_line=$bp_per_line\n"); 

my $width; 
my $height; 
my %bp_line_wind; 
$width  = $base_x * 2 + $opts{'width_per_line'}; 
my $max_idx_dep; 
my $wind_step; 
my $wind_minRatio; 
if ( $bp_per_line * 2/3 > $opts{'bp_overlap'} ) {
	$max_idx_dep = ($opts{'scfE'}-$opts{'scfS'}+1)/($bp_per_line-$opts{'bp_overlap'}); 
	$max_idx_dep == int($max_idx_dep) or $max_idx_dep = int($max_idx_dep)+1; 
} else {
	my $new_v = int( $bp_per_line * 2/3 ); 
	&tsmsg("[Wrn] The settings makes bp_per_line ($bp_per_line) too small compared to bp_overlap ($opts{'bp_overlap'}), so I decrease bp_overlap to $new_v\n"); 
	$opts{'bp_overlap'} = $new_v; 
	$max_idx_dep = ($opts{'scfE'}-$opts{'scfS'}+1)/($bp_per_line-$opts{'bp_overlap'}); 
	$max_idx_dep == int($max_idx_dep) or $max_idx_dep = int($max_idx_dep)+1; 
}
my $base_y_h = ( $base_y >= 50 ) ? $base_y : 50 ; 
$height = $base_y + $base_y_h + $step_y * $max_idx_dep; 
if ( $opts{'scfE'}-$opts{'scfS'}+1 <= ( ($opts{'bp_overlap'} ) ) ) {
	$wind_step = $bp_per_line; 
	$wind_minRatio = 0; 
} else {
	$wind_step = $bp_per_line - $opts{'bp_overlap'}; 
	$wind_minRatio = ($opts{'bp_overlap'}+1)/$bp_per_line; 
}
%bp_line_wind = %{ 
 $ms->setup_windows( 
   'ttl_start' => $opts{'scfS'}, 
   'ttl_end'   => $opts{'scfE'}, 
   'wind_size' => $bp_per_line, 
   'wind_step' => $wind_step, 
   'minRatio'  => $wind_minRatio, 
 ) 
}; 
# warn "$opts{'scfS'}, $opts{'scfE'}\n$bp_per_line - $opts{'bp_overlap'}, ($opts{'bp_overlap'}+1)/$bp_per_line\n"; 
my %si_to_idx; # {si} => index_of_line. 
for ( my $i=0; $i<@{$bp_line_wind{'info'}{'windSloci'}}; $i++ ) {
	$si_to_idx{ $bp_line_wind{'info'}{'windSloci'}[$i] } = $i+1; 
}


# SVG objects. 
my $svg = SVG->new('width'=>$width, 'height'=>$height); 
my %grps; 
$grps{'backbone'} = $svg->group(
	'id'                => "backbone_$opts{'scfID'}", 
	'stroke-width'      => 1, 
	'stroke'            => $color{'backbone'}, 
	'opacity'           => 1, 
	'text-anchor'       => 'middle', 
	'font-weight'       => 'normal', 
	'font-size'         => '10', 
	'font-family'       => 'ArialNarrow'
); # This is used to draw backbone of scaffold. 
$grps{'add_blks'} = $svg->group(
	'id'                => "add_blks_$opts{'scfID'}", 
	'stroke-width'      => 1, 
	'stroke'            => $color{'add_blks'}, 
	'fill'              => $color{'add_blks'}, 
	'opacity'           => 1, 
	'text-anchor'       => 'middle', 
	'font-weight'       => 'normal', 
	'font-size'         => '10', 
	'font-family'       => 'ArialNarrow'
); # This is used to draw add_blocks of scaffold. 
$grps{'tag_blks'} = $svg->group(
	'id'                => "tag_blks_$opts{'scfID'}", 
	'stroke-width'      => 1, 
	'stroke'            => $color{'tag_blks'}, 
	'fill'              => $color{'tag_blks'}, 
	'opacity'           => 1, 
	'text-anchor'       => 'middle', 
	'font-weight'       => 'normal', 
	'font-size'         => '10', 
	'font-family'       => 'ArialNarrow'
); # This is used to draw add_blocks of scaffold. 
$grps{'readpair_repeat'} = $svg->group(
	'id'                => "read_pairs_repeat", 
	'stroke-width'      => 0.5, 
	'stroke'            => $color{'readpair_repeat'}, 
	'opacity'           => 0.6, 
	'fill'              => 'transparent', 
	'text-anchor'       => 'middle', 
	'font-weight'       => 'normal', 
	'font-size'         => '10', 
	'font-family'       => 'ArialNarrow'
); # Draw read pairs aligned as 'XT:A:R/M'

$grps{'readpair_short'} = $svg->group(
	'id'                => "read_pairs_short", 
	'stroke-width'      => 0.2, 
	'stroke'            => $color{'readpair_short'}, 
	'opacity'           => 0.3, 
	'fill'              => 'transparent', 
	'text-anchor'       => 'middle', 
	'font-weight'       => 'normal', 
	'font-size'         => '10', 
	'font-family'       => 'ArialNarrow'
); # Draw read pairs. 

$grps{'readpair_long'} = $svg->group(
	'id'                => "read_pairs_long", 
	'stroke-width'      => 0.2, 
	'stroke'            => $color{'readpair_long'}, 
	'opacity'           => 0.3, 
	'fill'              => 'transparent', 
	'text-anchor'       => 'middle', 
	'font-weight'       => 'normal', 
	'font-size'         => '10', 
	'font-family'       => 'ArialNarrow'
); # Draw read pairs. 

$grps{'readpair'} = $svg->group(
	'id'                => "read_pairs", 
	'stroke-width'      => 0.5, 
	'stroke'            => $color{'readpair'}, 
	'opacity'           => 0.6, 
	'fill'              => 'transparent', 
	'text-anchor'       => 'middle', 
	'font-weight'       => 'normal', 
	'font-size'         => '10', 
	'font-family'       => 'ArialNarrow'
); # Draw read pairs. 

# Raw scaffoldID ; 
$grps{'backbone'}->text(
 'x'       => $base_x/2, 
 'y'       => $base_y_h * 1/2, 
 -cdata    => "scfID=[$opts{'scfID'}] $opts{'scfS'}-$opts{'scfE'}", 
 'font-weight' => "bold", 
 'font-size'   => 20, 
 'text-anchor' => 'start', 
); 

# Draw ticks. 
for (my $i=0; $i<=$opts{'scfE'}; $i+=$opts{'tickStep'}) {
	$i >= $opts{'scfS'}-1 or next; 
	my @si = @{ 
	 $ms->map_windows( 
	   'position'  => $i, 
	   'wind_hash' => \%bp_line_wind, 
	 ) 
	}; 
	my $show_v = $i/$unit_len; 
	$show_v .= $opts{'tickUnit'}; 
	for my $tsi (@si) {
		my $idx_dep = $si_to_idx{$tsi}; 
		$grps{'backbone'}->line(
		 'x1' => $base_x+($i-$bp_line_wind{'loci'}{$tsi}[0]+1)/$opts{'bp_per_point'}, 
		 'y1' => $base_y+$idx_dep*$step_y, 
		 'x2' => $base_x+($i-$bp_line_wind{'loci'}{$tsi}[0]+1)/$opts{'bp_per_point'}, 
		 'y2' => $base_y+$idx_dep*$step_y+5, 
		); 
		$grps{'backbone'}->text(
		 'x'       => $base_x+($i-$bp_line_wind{'loci'}{$tsi}[0]+1)/$opts{'bp_per_point'}, 
		 'y'       => $base_y+$idx_dep*$step_y+15, 
		 -cdata    => "$show_v", 
		 'font-weight' => 'lighter', 
		); 
	}
}

# Draw backbone lines. 
my %has_draw_bb_idx_dep; 
for ( my $lineS=$opts{'scfS'}; $lineS<=$opts{'scfE'}; $lineS+=$wind_step ) {
	my $lineE = $lineS+$bp_per_line-1; 
	$lineE > $opts{'scfE'} and $lineE = $opts{'scfE'}; 
	my @si = @{ 
	 $ms->map_windows( 
	   'position'  => $lineS, 
	   'wind_hash' => \%bp_line_wind, 
	 ) 
	}; 
	for my $tsi (@si) {
		my $idx_dep = $si_to_idx{$tsi}; 
		defined $has_draw_bb_idx_dep{$idx_dep} and next; 
		$has_draw_bb_idx_dep{$idx_dep} = 1; 
		$grps{'backbone'}->line(
		 'x1' => $base_x, 
		 'y1' => $base_y+$idx_dep*$step_y, 
		 'x2' => $base_x+($lineE-$lineS+1)/$opts{'bp_per_point'}, 
		 'y2' => $base_y+$idx_dep*$step_y, 
		); 
	}
}

# Draw add_blks lines. 
my %used_id; 
for my $tr (@add_blks) {
	my ($s, $e) = @$tr; 
	$e < $opts{'scfS'} and next; 
	$s > $opts{'scfE'} and next; 
	$s >= $opts{'scfS'} or $s = $opts{'scfS'}; 
	$e <= $opts{'scfE'} or $e = $opts{'scfE'}; 
	# for ( my $i=1; $i<=$e; $i+=($bp_per_line - $opts{'bp_overlap'}) ) {
	for ( my $i=$opts{'scfS'}; $i<=$e; $i+=$wind_step ) {
		my $blkS = $i; 
		my $blkE = $i+$bp_per_line-1; 
		$blkE < $s and next; 
		$blkE > $e and $blkE = $e; 
		$blkS < $s and $blkS = $s; 
		my @si = @{ 
		 $ms->map_windows( 
		   'position'  => $blkS, 
		   'wind_hash' => \%bp_line_wind, 
		 ) 
		}; 
		for my $tsi (@si) {
			$i == $tsi or next; 
			my $idx_dep  = $si_to_idx{$tsi}; 
			my $cur_s    = $blkS-$bp_line_wind{'loci'}{$tsi}[0]+1; 
			my $cur_e    = $blkE-$bp_line_wind{'loci'}{$tsi}[0]+1; 
			my $cur_x_s  = $base_x + $cur_s/$opts{'bp_per_point'}; 
			my $cur_x_e  = $base_x + $cur_e/$opts{'bp_per_point'}; 
			my $tk = "$blkS - $blkE"; 
			my $n = 0; 
			while (defined $used_id{$tk}) {
				$tk = "$blkS - $blkE : $n"; 
				$n++; 
				$n > 10000 and die "Problem tk=$tk\n"; 
			}
			$grps{'add_blks'}->rectangle(
			 'x'      => $cur_x_s, 
			 'y'      => $base_y+$idx_dep*$step_y-8, 
			 'width'  => $cur_x_e-$cur_x_s, 
			 'height' => 5, 
			 'id'     => "$tk", 
			); 
			$used_id{$tk} = 1; 
		}
	}
}

# Draw tag_blks lines. 
my %used_id_tag; 
for my $tr (@tag_blks) {
	my ($s, $e) = @$tr; 
	$e < $opts{'scfS'} and next; 
	$s > $opts{'scfE'} and next; 
	$s >= $opts{'scfS'} or $s = $opts{'scfS'}; 
	$e <= $opts{'scfE'} or $e = $opts{'scfE'}; 
	# for ( my $i=1; $i<=$e; $i+=($bp_per_line - $opts{'bp_overlap'}) ) {
	for ( my $i=$opts{'scfS'}; $i<=$e; $i+=$wind_step ) {
		my $blkE = $i+$bp_per_line-1; 
		my $blkS = $i; 
		$blkE < $s and next; 
		$blkE > $e and $blkE = $e; 
		$blkS < $s and $blkS = $s; 
		my @si = @{ 
		 $ms->map_windows( 
		   'position'  => $blkS, 
		   'wind_hash' => \%bp_line_wind, 
		 ) 
		}; 
		for my $tsi (@si) {
			$i == $tsi or next; 
			my $idx_dep  = $si_to_idx{$tsi}; 
			my $cur_s    = $blkS-$bp_line_wind{'loci'}{$tsi}[0]+1; 
			my $cur_e    = $blkE-$bp_line_wind{'loci'}{$tsi}[0]+1; 
			my $cur_x_s  = $base_x + $cur_s/$opts{'bp_per_point'}; 
			my $cur_x_e  = $base_x + $cur_e/$opts{'bp_per_point'}; 
			my $tk = "tag: $blkS - $blkE"; 
			my $n = 0; 
			while (defined $used_id_tag{$tk}) {
				$tk = "tag: $blkS - $blkE : $n"; 
				$n++; 
				$n > 10000 and die "Problem tk=$tk\n"; 
			}
			$grps{'tag_blks'}->rectangle(
			 'x'      => $cur_x_s, 
			 'y'      => $base_y+$idx_dep*$step_y, 
			 'width'  => $cur_x_e-$cur_x_s, 
			 'height' => 3, 
			 'id'     => "$tk", 
			); 
			$used_id_tag{$tk} = 1; 
		}
	}
}


# Draw read pairs. 
#   Draw read pairs. 
for my $tr (@pair_se) {
	my ($s, $e, $xt_u) = @$tr; 
	my $grp_key; 
	if ( $xt_u == 0 ) {
		$grp_key = 'readpair_repeat'; 
	} else  {
		$grp_key = 'readpair'; 
		$opts{'limit_short'} > 0 and $opts{'limit_short'} > $e-$s+1 and $grp_key = 'readpair_short'; 
		$opts{'limit_long'}  > 0 and $opts{'limit_long'}  < $e-$s+1 and $grp_key = 'readpair_long'; 
	}
	my @si_s = @{
	 $ms->map_windows(
	   'position'  => $s, 
	   'wind_hash' => \%bp_line_wind, 
	 )
	}; 
	my @si_e = @{
	 $ms->map_windows(
	   'position'  => $e, 
	   'wind_hash' => \%bp_line_wind, 
	 )
	}; 
	for my $tsi_s (@si_s) {
		my $idx_dep = $si_to_idx{$tsi_s}; 
		my $cur_s = $s-$bp_line_wind{'loci'}{$tsi_s}[0]+1; 
		my $cur_x_s  = $base_x + $cur_s/$opts{'bp_per_point'}; 
		for my $tsi_e (@si_e) {
			$tsi_s == $tsi_e or next; 

			my $cur_e = $e-$bp_line_wind{'loci'}{$tsi_e}[0]+1; 
			my $cur_x_e  = $base_x + $cur_e/$opts{'bp_per_point'}; 
			my $cur_y_se = $base_y+$idx_dep*$step_y; 
			my @xx = ( $cur_x_s,  ($cur_x_s+$cur_x_e)/2, $cur_x_e ); 
			my @yy = ( $cur_y_se-10, $cur_y_se-$rdHeight_y, $cur_y_se-10 ); 
			my $points = $grps{$grp_key}->get_path(
				'x'   => \@xx, 
				'y'   => \@yy, 
				-relative=>1, 
				-type=>'polyline',
				-closed=>0
			); 
			$grps{$grp_key}->polyline(%$points); 
		}
	}
}


print {$outFh} $svg->xmlify; 



