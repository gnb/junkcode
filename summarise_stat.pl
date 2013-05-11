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
# Updated 20130511 to correctly diagnose 64b executables
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
my @summ;
my $nbroken = 0;
my $total = 0;
my $debug = 0;
my @broken_by_status;

# Parse arguments
@pathnames = @ARGV;

my @status_strings =
(
	"cannot be read (permission denied)",
	"are scripts (shell, perl, whatever)",
	"are 64-bit executables",
	"don't use any stat() family calls at all",
	"use 32-bit stat() family interfaces only",
	"use 64-bit stat64() family interfaces only",
	"use both 32-bit and 64-bit stat() family interfaces",
);
my @status_broken = (
	0,
	0,
	0,
	0,
	1,
	0,
	1
);

sub MAX_STATUS { return 6 };
sub status
{
	my ($r) = @_;
	return 0 if ($r->{no_perm});
	return 1 if ($r->{not_exe});
	return 2 if ($r->{elf64b});
	return 3 + ($r->{used64} ? 2 : 0) + ($r->{used32} ? 1 : 0);
}

map { $summ[$_] = 0 } (0..MAX_STATUS);
map { $broken_by_status[$_] = [] } (0..MAX_STATUS);

# Function to scan a file
sub scan_file
{
	my ($path) = @_;
	my $fh;

	my %res =
	(
		elf64b => 0,
		used32 => 0,
		used64 => 0,
		not_exe => 0,
		no_perm => 0,
	);

	open $fh,'-|', "file -L \"$path\" 2>&1"
		or return;
	$_ = readline $fh;
	chomp;
	if (m/ELF 64-bit/)
	{
		$res{elf64b} = 1;
	}
	close $fh;
	$fh = undef;

	open $fh,'-|', "nm -uD \"$path\" 2>&1"
		or return;
	while (<$fh>)
	{
		chomp;

		if (m/File format not recogni[sz]ed/)
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

	print "$res{used32} $res{used64} $res{not_exe} $res{no_perm} $res{elf64b} $path\n" if $debug;

	my $s = status(\%res);
	if ($status_broken[$s])
	{
	    push(@{$broken_by_status[$s]}, $path);
	    $nbroken++;
	}
	$summ[$s]++;
	$total++;
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

{
}

# generate a summary
print "Summary by status\n";
print "-----------------\n";
foreach my $s (0..MAX_STATUS)
{
	next if $summ[$s] == 0;
	printf "%7d %4.1f%% %s%s\n",
		$summ[$s], (100.0 * $summ[$s] / $total), $status_strings[$s],
		($status_broken[$s] ? " [BROKEN]" : "");
}
printf "%7d %4.1f%% BROKEN\n",
	$nbroken, (100.0 * $nbroken / $total);

# list all broken files
if ($nbroken)
{
	print "List of broken files\n";
	print "--------------------\n";
	foreach my $s (0..MAX_STATUS)
	{
		next if !$status_broken[$s];
		next if !scalar(@{$broken_by_status[$s]});
		printf "These %s\n", $status_strings[$s];
		map { printf "    %s\n", $_; } @{$broken_by_status[$s]};
	}
}
