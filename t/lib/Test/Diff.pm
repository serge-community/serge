package Test::Diff;

use strict;

use vars qw(@ISA @EXPORT);

require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(files_diff dir_diff);

use Digest::MD5;
use File::Find qw/find/;
use File::Spec::Functions qw/abs2rel catfile/;
use Test::More;
use Text::Diff;

sub file_md5 {
    my $filepath = shift;
    return undef unless -f $filepath;

    my $md5 = Digest::MD5->new;

    open my $f, $filepath;
    binmode $f;
    $md5->addfile($f);
    close $f;

    return $md5->digest;
}

sub files_diff {
    my ($f1, $f2, $opt) = @_;

    my $base = defined($opt) && exists($opt->{base_dir}) ? $opt->{base_dir} : undef;

    my ($fr1, $fr2) = map { $base ? abs2rel($_, $base) : $_} ($f1, $f2);

    my $ok = 1;

    $ok &= fail "File '$f1' should exist" unless -f $f1;
    $ok &= fail "File '$f2' should exist" unless -f $f2;

    $ok &= ok(file_md5($f1) eq file_md5($f2), "Files '$fr1' and '$fr2' should be equal") if $ok;
    diag(diff($f1, $f2, { STYLE => "Table", FILENAME_A => $fr1, FILENAME_B => $fr2} )) if !$ok;
}

sub dir_diff {
    my ($d1, $d2, $opt) = @_;

    my $base = defined($opt) && exists($opt->{base_dir}) ? $opt->{base_dir} : undef;

    my ($dr1, $dr2) = map { $base ? abs2rel($_, $base) : $_ } ($d1, $d2);

    # skip the test if there's no reference dir and no target dir
    return ok(1, "Both '$dr1' and '$dr2' directories shouldn't exist") if !-d $dr1 && !-d $dr2;

    fail "Directory '$dr1' exists but '$dr2' doesn't" if -d $dr1 && !-d $dr2;
    fail "Directory '$dr1' doesn't exist but '$dr2' does" if !-d $dr1 && -d $dr2;

    my $msg = "Compare directory '$dr1' with '$dr2'";

    return subtest $msg => sub {
        find(sub {
            my $t1 = $File::Find::name;
            my $t2 = catfile($d2, abs2rel($t1, $d1));

            files_diff($t1, $t2, { base_dir => $base }) if (-f $t1);
        }, $d1);

        find(sub {
            my $t1 = $File::Find::name;
            my $t2 = catfile($d1, abs2rel($t1, $d2));

            files_diff($t1, $t2, { base_dir => $base }) if (-f $t1);
        }, $d2);
    };
}

1;