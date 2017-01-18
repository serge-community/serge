#!/usr/bin/env perl

use strict;

use Cwd qw(abs_path);
use File::Basename;
use File::Find qw(find);
use File::Spec::Functions qw(catfile);
use Test::More;

my $thisdir = dirname(abs_path(__FILE__));
my $libpath = catfile($thisdir, '../lib');

my @tests;
map {
    find(sub {
        push @tests, $File::Find::name if (-f $_ && /\.(pl|pm|t)$/);
    }, catfile($thisdir, $_));
} qw(../bin ../lib .);

foreach my $file (@tests) {
    require_ok $file;
}

done_testing();