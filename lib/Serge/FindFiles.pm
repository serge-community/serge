package Serge::FindFiles;

use strict;
use utf8;

no utf8;
no warnings qw(uninitialized);

use Config::Neat::Util qw(is_array is_neat_array);
use File::Spec::Functions qw(rel2abs catfile);

sub new {
    my ($class, $self) = @_;

    $self = {} unless defined $self;

    # Exclude `.svn', `.git', `.hg' (Mercurial), '.bzr' (Bazaar) and `CVS' dirs (case-sensitive) from processing by default
    $self->{dir_exclude} = ['^(\.svn|\.git|\.hg|\.bzr|CVS)$'] unless exists $self->{dir_exclude};

    bless $self, $class;
    return $self;
}

sub find {
    my ($self, $dir) = @_;

    # Perform sanity checks
    die "'prefix' property must be a scalar value" if exists $self->{prefix} && !(defined $self->{prefix} && (ref(\$self->{prefix}) eq 'SCALAR'));
    die "'postcheck_callback' property must be a code reference" if exists $self->{postcheck_callback} && (ref($self->{postcheck_callback}) ne 'CODE');

    map {
        die "'$_' property must be an array reference" if exists $self->{$_} && !(is_array($self->{$_}) || is_neat_array($self->{$_}));
    } qw(match dir_match dir_exclude exclude);

    # Initialize the output hash and process the dir recursively

    $self->{found_files} = {};
    $self->process_subdir(rel2abs($dir), '');
}

sub process_subdir {
    my ($self, $dir, $relpath) = @_;

    opendir(my $dh, $dir);
    while (my $name = readdir $dh) {
        if ($^O !~ /MSWin32/) { # assume we are on Unix if not on Windows
            utf8::decode($name); # assume UTF8 filenames
        }
        next if $name eq '.' || $name eq '..';
        my $subpath = $relpath ne '' ? $relpath.'/'.$name : $name; # relative path is always delimited by a forward slash (relative paths are platform-independent)
        my $fullpath = catfile($dir, $name);
        my $file_rel = $self->{prefix}.$subpath;

        if (-d $fullpath) {
            if ($self->{process_subdirs} && $self->check_path($file_rel, $name)) {
                $self->process_subdir($fullpath, $subpath);
            }
        } elsif (-f $fullpath) {
            if ($self->check_path($file_rel, $name, 1)) {
                if (exists $self->{postcheck_callback}) {
                    $file_rel = &{$self->{postcheck_callback}}($file_rel, $fullpath);
                }
                $self->{found_files}->{$file_rel} = 1;
            }
        }
    }
    closedir $dh;
}

sub check_path {
    my ($self, $path, $name, $file_mode) = @_;

    my $ok = undef;

    if ($file_mode) {
        # Test if relative file path (or file name) matches the mask
        if (exists $self->{match}) {
            foreach my $rule (@{$self->{match}}) {
                if (($name =~ m/$rule/) || ($path =~ m/$rule/)) {
                    $ok = 1;
                    last;
                }
            }
        } else {
            # If 'match' not provided, gather all files
            $ok = 1;
        }
    } else {
        # Test if relative directory path (or directory name) matches the mask
        if (exists $self->{dir_match}) {
            foreach my $rule (@{$self->{dir_match}}) {
                if (($name =~ m/$rule/) || ($path =~ m/$rule/)) {
                    $ok = 1;
                    last;
                }
            }
        } else {
            # If 'dir_match' not provided, go through all directories
            $ok = 1;
        }
    }

    if (!$file_mode) {
        # Test if relative directory path (or directory name) does not match the directory-specific exclusion mask
        if ($ok && exists $self->{dir_exclude}) {
            foreach my $rule (@{$self->{dir_exclude}}) {
                if (($name =~ m/$rule/) || ($path =~ m/$rule/)) {
                    $ok = undef;
                    last;
                }
            }
        }
    }

    # Test if relative file/directory path (or file/directory name) does not match the exclusion mask
    if ($ok && exists $self->{exclude}) {
        foreach my $rule (@{$self->{exclude}}) {
            if (($name =~ m/$rule/) || ($path =~ m/$rule/)) {
                $ok = undef;
                last;
            }
        }
    }

    return $ok;
}

1;