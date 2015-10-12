package Serge::Sync::Util;

use strict;

our @ISA = qw(Exporter);

our @EXPORT = qw(
    escape_path
    get_directory_contents
);

sub escape_path {
    my $path = shift;

    if ($^O !~ /MSWin32/) { # assume we are on Unix if not on Windows
        $path =~ s/\$/\\\$/sg; # escape dollar sign
    }

    return $path;
}

# return top-level directory contents (files and folder names)
sub get_directory_contents {
    my $path = shift;
    $path = '.' unless $path;

    opendir my $dir, $path or die "Can't open directory '$path': $!";
    my @a = grep {!/^\.+$/} readdir $dir; # grep everything except '.' and '..'
    closedir $dir;

    return @a;
}

1;