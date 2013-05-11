#!/usr/bin/perl
#
# A Perl script for evaluating and summarising which executables in
# the given directories depend on the old 32-bit stat() family APIs.
#
# Usage: summarise_stat.pl directory [...]
#
# Copyright (c) 2007 Silicon Graphics, Inc.  All Rights Reserved.
# By Greg Banks <gnb@melbourne.sgi.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

use strict;
use warnings;

my @pathnames;		# file and directories to read, from the commandline
my @results;		# array of { path, used32, used64, not_exe, no_perm } hashes
my $debug = 0;

# Parse arguments
@pathnames = @ARGV;

# Function to scan a file
sub scan_file
{
	my ($path) = @_;
	my $fh;
	
	my %res =
	(
		path => $path,
		used32 => 0,
		used64 => 0,
		not_exe => 0,
		no_perm => 0,
	);

	open $fh,'-|', "nm -uD \"$path\" 2>&1"
		or return;
	while (<$fh>)
	{
		chomp;

		if (m/File format not recognized/)
		{
			$res{not_exe} = 1;
		}
		elsif (m/Permission denied/)
		{
			$res{no_perm} = 1;
		}
		elsif (m/^\s+U __(|l|f)xstat$/)
		{
			$res{used32}++;
		}
		elsif (m/^\s+U __(|l|f)xstat64$/)
		{
			$res{used64}++;
		}
	}
	close $fh;
	push(@results, \%res);
}

# Function to scan a directory
sub scan_directory
{
	my ($path) = @_;
	my $dh;
	return unless opendir($dh,$path);
	while (my $d = readdir $dh)
	{
		next if ($d =~ m/^\./);
		print "$path/$d\n" if $debug;
		scan_path("$path/$d");
	}
	closedir $dh;
}

# Function to scan something that might be a file or a directory
sub scan_path
{
	my ($path) = @_;
	print "scan_path($path)\n" if $debug;
	if ( -d $path )
	{
		scan_directory($path);
	}
	elsif ( -e $path )
	{
		scan_file($path);
	}
}

# Scan files and directories specified in the commandline
foreach my $path (@pathnames)
{
	scan_path($path);
}

my @status_strings =
(
	"cannot be read (permission denied)",
	"are scripts (shell, perl, whatever)",
	"don't use any stat() family calls at all",
	"use 32-bit stat() family interfaces only",
	"use 64-bit stat64() family interfaces only",
	"use both 32-bit and 64-bit stat() family interfaces",
);

sub MAX_STATUS { return 5 };
sub status
{
	my ($r) = @_;
	return 0 if ($r->{no_perm});
	return 1 if ($r->{not_exe});
	return 2 + ($r->{used64} ? 2 : 0) + ($r->{used32} ? 1 : 0);
}

# Function to generate a summary
sub emit_summary
{
	my @summ;
	my $total = 0;

	foreach my $r (@results)
	{
		my $s = status($r);
		$summ[$s] = 0 unless defined $summ[$s];
		$summ[$s]++;
		$total++;
	}

	foreach my $s (0..MAX_STATUS)
	{
		next unless defined $summ[$s];
		printf "%7d %4.1f%% %s\n",
			$summ[$s], (100.0 * $summ[$s] / $total), $status_strings[$s];
	}
}

# Function to dump raw data
sub emit_raw
{
	foreach my $r (@results)
	{
		print "$r->{used32} $r->{used64} $r->{not_exe} $r->{no_perm} $r->{path}\n";
	}
}

emit_raw if $debug;
emit_summary;

