#!/usr/bin/env perl
# Copyright (C) 2021, Lucian Paul-Trifu.  All rights reserved.

use strict;
use Date::Parse;

my $A_PAST_MONDAY = str2time "Jun 1 2020";
my $DAY_S = 86400;
my $WEEK_S = $DAY_S * 7;

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
	if (!defined $start) {
		$start = str2time($date) if !defined $start;
	} else {
		my $duration = str2time($date) - $start;
		undef $start;
		$durations{$day} += $duration;
	}
}
close $if or die "Cannot read PM logs";

my %days = map { str2time($_) => $_ } keys %durations;
my @days = sort { $a <=> $b } (keys %days);
my $first_day_aligned = $days[0] - (($days[0] - $A_PAST_MONDAY) / $DAY_S % 7 * $DAY_S);
my $last_day_aligned  = $days[-1] + ((7 - ($days[-1] - $A_PAST_MONDAY) / $DAY_S % 7) * $DAY_S);

for (my $w_start = $first_day_aligned; $w_start < $last_day_aligned; $w_start += $WEEK_S) {
	my $w_end = $w_start + $WEEK_S;
	#my $we_start = $w_end - 2 * $DAY_S 
	for (my $d = $w_start; $d < $w_end; $d += $DAY_S) {
		print $days{$d} // "\t";
		last if defined $days{$d};
	}
	print "\n";
	my @hours;
	for (my $d = $w_start; $d < $w_end; $d += $DAY_S) {
		my $half_hour = $durations{$days{$d}} % 3600 >= 1800 ? .5 : 0;
		push @hours, defined $days{$d} ? int($durations{$days{$d}} / 3600) + $half_hour : 0;
	}
	my $we_hours = $hours[-2] + $hours[-1];
	print join("\t", @hours[0..($#hours-2)]), "\n";
	print (("\t") x 5, "Weekend ", $we_hours, "\n") if $we_hours;
}
