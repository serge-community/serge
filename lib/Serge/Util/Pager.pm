package Serge::Util::Pager;

use strict;
use utf8;

use Getopt::Long;

our @ISA = qw(Exporter);

my $no_pager;
GetOptions(
    'no-pager' => \$no_pager,
) or die "Failed to parse some command-line parameters.";

my ($file_handle, $can_close);

sub init {
    my $pager;

    # disable pager if STDOUT is not tied to an interactive terminal
    # or if --no-pager option has been provided on a command line
    if (-t STDOUT && !$no_pager) {
        if (!exists $ENV{'SERGE_PAGER'} && !exists $ENV{'PAGER'}) {
            # test if `less` pager is available; under Windows, this usually comes
            # with other *nix utilities, including `which` (installed along with e.g. Git).
            # so this either works together (`which less`) or doesn't work at all
            `which less 2>&1`;
            my $error_code = unpack 'c', pack 'C', $? >> 8; # error code
            $pager = 'less -XFR' if ($error_code == 0);

            # `more' pager is available under both *nix and Windows
            $pager = 'more' unless $pager;
        } else {
            $pager = $ENV{'PAGER'};
            $pager = $ENV{'SERGE_PAGER'} if exists $ENV{'SERGE_PAGER'};
        }
    }

    if ($pager) {
        open $file_handle, "|$pager" or die "Unable to start pager [$pager]: $!";
        $can_close = 1;
    } else {
        $file_handle = \*STDOUT;
    }

    return $file_handle;
}

sub print {
    die "Pager file handle is undefined" unless defined $file_handle;
    print $file_handle @_;
}

sub close {
    if ($can_close) {
        close $file_handle or die "Unable to close pager: $!";;
        undef $file_handle;
        undef $can_close;
    }
}

1;
