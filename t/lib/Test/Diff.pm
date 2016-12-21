package Test::Diff;

use strict;

use vars qw(@ISA @EXPORT);

require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(files_diff dir_diff);

use File::Find qw/find/;
use File::Spec::Functions qw/abs2rel/;
use Test::More;
use Test::Files;

sub dir_diff {
    my ($d1, $d2, $opt) = @_;

    my $base = defined($opt) && exists($opt->{base_dir}) ? $opt->{base_dir} : undef;

    my ($dr1, $dr2) = map { $base ? abs2rel($_, $base) : $_ } ($d1, $d2);

    # skip the test if there's no reference dir and no target dir
    return ok(1, "Both '$dr1' and '$dr2' directories shouldn't exist") if !-d $dr1 && !-d $dr2;

    fail "Directory '$dr1' exists but '$dr2' doesn't" if -d $dr1 && !-d $dr2;
    fail "Directory '$dr1' doesn't exist but '$dr2' does" if !-d $dr1 && -d $dr2;

    compare_dirs_ok $dr1, $dr2, "The files in '$dr1' are the same as the files in '$dr2'.";
}

1;