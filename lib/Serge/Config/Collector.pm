package Serge::Config::Collector;

use strict;

use Cwd;
use File::Spec::Functions qw(rel2abs catfile);
use File::Basename;
use Serge::Config;
use Serge::FindFiles;
use Serge::Util;

sub new {
    my ($class, @paths) = @_;

    my $self = {
        config_lookup_paths => \@paths,
        config_files => {}
    };

    bless $self, $class;

    $self->gather_config_files;
    $self->parse_configs;

    return $self;
}

sub gather_config_files {
    my ($self) = @_;

    $self->{config_files} = {};

    my $has_params;

    foreach (@{$self->{config_lookup_paths}}) {
        # if @ARGV is passed, we need to filter out
        # command-line parameters that start with '--'
        if ($_ !~ m/^--/) {
            $has_params = 1;
            $self->gather_config_from_path($_); # not recursively
        }
    }

    if (!$has_params) {
        $self->gather_config_from_path(getcwd); # not recursively
    }
}

sub gather_config_from_path {
    my ($self, $path, $recursively) = @_;

    $path = rel2abs($path);

    if (-f $path) {
        $self->{config_files}->{catfile($path)} = 1;
    } elsif (-d $path) {
        print "Scanning .serge files in '$path'...";
        my $n = 0;

        my $ff = Serge::FindFiles->new({
            match => ['\.serge$'],
            process_subdirs => $recursively,
            postcheck_callback => sub {
                my ($file_rel, $fullpath) = @_;
                $n++;
                $self->{config_files}->{$fullpath} = 1;
            }
        });
        $ff->find($path);

        print " $n files found\n";
    } else {
        die "'$path' doesn't point to an existing file or directory";
    }
}

sub parse_configs {
    my ($self) = @_;

    foreach my $config_file (keys %{$self->{config_files}}) {
        eval {
            $self->{config_files}->{$config_file} = Serge::Config->new($config_file);
        };
        if ($@) {
            die "Exception in configuration file '$config_file': $@\n";
        }
    }
}

sub get_config_files {
    my ($self) = @_;
    return sort keys %{$self->{config_files}};
}

sub get_config_object {
    my ($self, $config_file) = @_;
    return $self->{config_files}->{$config_file};
}

sub get_db_sources {
    my ($self) = @_;

    my %db_sources;
    my @res;

    foreach my $config_file (keys %{$self->{config_files}}) {
        my $cfg = $self->get_config_object($config_file);
        my $cfg_db_sources = $cfg->get_db_sources;
        @db_sources{keys %$cfg_db_sources} = values %$cfg_db_sources;
    }

    return \%db_sources;
}

1;