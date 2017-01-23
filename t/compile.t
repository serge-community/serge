#!/usr/bin/env perl

use strict;

BEGIN {
    use Cwd qw(abs_path);
    use File::Basename;
    use File::Spec::Functions qw(catfile);
    map { unshift(@INC, catfile(dirname(abs_path(__FILE__)), $_)) } qw(../lib);
}

use File::Find qw(find);
use Test::More;

my $thisdir = dirname(abs_path(__FILE__));
my $libpath = catfile($thisdir, '../lib');

my @tests;
map {
    find(sub {
        push @tests, $File::Find::name if (-f $_ && /\.(pl|pm|t)$/);
    }, catfile($thisdir, $_));
} qw(../bin ../lib .);

for (@tests) {
    my $output;
    if (m/\.pm$/) {
        eval { $output = do $_ };
        ok(!$@ && $output, "'do' $_");
    } else {
        $output = `perl -I "$libpath" -c $_ 2>&1`;
        my $ok = ($? >> 8 == 0);
        ok($ok, "$_ syntax check");
    }
}

done_testing();