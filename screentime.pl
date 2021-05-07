#!/usr/bin/env perl
# Copyright (C) 2021, Lucian Paul-Trifu.  All rights reserved.

use strict;
use Date::Parse;
use List::Util qw(min max);

my $A_PAST_MONDAY = str2time "Jun 1 2020";
my $DAY_S = 86400;
my $WEEK_S = $DAY_S * 7;

# Note: get_clock_change() needs day date timestamps for a meaningful result.
sub get_clock_change {
	my ($day1, $day2) = @_;
	my $diff = $day2 - $day1;
	return $diff - $DAY_S * sprintf("%.0f", $diff / $DAY_S);
}

# Note: the alignment functions do not apply to the
# result any real-world clock change.
sub align_down_to_monday {
	my $day = @_[0];
	return $day - ($day - ($A_PAST_MONDAY + get_clock_change($A_PAST_MONDAY, $day))) / $DAY_S % 7 * $DAY_S;
}
sub align_up_to_monday {
	my $day = @_[0];
	return $day + (($A_PAST_MONDAY + get_clock_change($A_PAST_MONDAY, $day)) - $day) / $DAY_S % 7 * $DAY_S;
}


open my $if, "-|", 'syslog -f /var/log/powermanagement/*.asl 2>/dev/null | '
   .'sed -E -n \'/Display is turned on$/,$ p\'';
   #.'s/^(([^[:space:]]+[[:space:]]){3}).*Display is turned (on|off)$/\1/p\'';

my $start;
my %durations;
while (<$if>) {
	next if !/^(((?:[^\s]+\s+){2})([^\s]+)).*Display is turned (on|off)$/;
	#next if !/^((?:[^\s]+\s+){3}).*Display is turned (on|off)$/;
	my $date = $1;
	my $day = $2;
	my $display_state = $4;
	if (!defined $start) {
		$start = str2time($date) if $display_state eq "on";
	} elsif ($display_state eq "off") {
		my $duration = str2time($date) - $start;
		undef $start;
		$durations{$day} += $duration;
	}
}
close $if or die "Cannot read PM logs";

my %days = map { str2time($_) => $_ } keys %durations;
my @days = sort { $a <=> $b } (keys %days);
my $first_day_aligned = align_down_to_monday($days[0]);
my $last_day_aligned = align_up_to_monday($days[-1]);

my $clock_change = 0;
my $first_day_with_clock_changed;
my $first_day_with_clock_changed_aligned;
for (my $i = 0; $i < @days - 1; $i += 2) {
	$clock_change = get_clock_change($days[$i], $days[$i + 1]);
	if ($clock_change) {
		$first_day_with_clock_changed = $days[$i + 1];
		$first_day_with_clock_changed_aligned =
		              align_up_to_monday($first_day_with_clock_changed);
		last;
	}
}

for (my $w_start = $first_day_aligned; $w_start < $last_day_aligned; $w_start += $WEEK_S) {
	$w_start += $clock_change if $clock_change &&
	        $w_start == ($first_day_with_clock_changed_aligned - $clock_change);
	my $w_end = $w_start + $WEEK_S;
	#my $we_start = $w_end - 2 * $DAY_S 
	for (my $d = $w_start; $d < $w_end; $d += $DAY_S) {
		$d += $clock_change if $clock_change &&
		    $d == ($first_day_with_clock_changed - $clock_change);
		print $days{$d} // "\t";
		last if defined $days{$d};
	}
	print "\n";
	my @hours;
	for (my $d = $w_start; $d < $w_end; $d += $DAY_S) {
		$d += $clock_change if $clock_change &&
		    $d == ($first_day_with_clock_changed - $clock_change);
		my $half_hour = $durations{$days{$d}} % 3600 >= 1800 ? .5 : 0;
		push @hours, defined $days{$d} ? int($durations{$days{$d}} / 3600) + $half_hour : 0;
	}
	my $we_hours = $hours[-2] + $hours[-1];
	print join("\t", @hours[0..($#hours-2)]), "\n";
	print (("\t") x 5, "Weekend ", $we_hours, "\n") if $we_hours;
}
