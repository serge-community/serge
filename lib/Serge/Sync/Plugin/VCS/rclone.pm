package Serge::Sync::Plugin::VCS::rclone;
use parent Serge::Plugin::Base, Serge::Interface::SysCmdRunner;

use strict;

use File::Spec::Functions qw(catfile);
use Serge::Util qw(subst_macros);

sub name {
    return 'Rclone sync wrapper plugin';
}

sub support_branch_switching {
    return 1;
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        config         => 'STRING',
        parameters     => 'ARRAY',

        pull => {
            source     => 'STRING',
            dest       => 'STRING',
            parameters => 'ARRAY'
        },

        push => {
            source     => 'STRING',
            dest       => 'STRING',
            parameters => 'ARRAY'
        }
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    if (!exists $self->{data}->{pull} && !exists $self->{data}->{push}) {
        die "'pull' or 'push' section must be defined";
    }

    my $config = $self->{data}->{config};
    if ($config ne '') {
        $config = subst_macros($config);
        die "Config path evaluates to an empty value" if $config eq '';

        $config = $self->{parent}->abspath($config);
        die "Config file doesn't exist: $config" unless -f $config;

        print "Will use rclone config file located at $config\n";
    } else {
        print "Will use a default rclone config file\n";
    }
    $self->{data}->{config} = $config;
}

sub checkout_all {
    my ($self, $message) = @_;

    if (!exists $self->{data}->{pull}) {
        print "No pull configuration provided; nothing to do\n";
        return;
    }

    $self->_rclone_sync($self->{data}->{pull});
}

sub commit_all {
    my ($self, $message) = @_;

    if (!exists $self->{data}->{push}) {
        print "No push configuration provided; nothing to do\n";
        return;
    }

    $self->_rclone_sync($self->{data}->{push});
}

sub _rclone_sync {
    my ($self, $data) = @_;

    my $config = $self->{data}->{config};
    my $source = subst_macros($data->{source});
    my $dest = subst_macros($data->{dest});

    my @params;

    # add global parameters
    if (exists $self->{data}->{parameters}) {
        push @params, @{$self->{data}->{parameters}};
    }

    # append local parameters
    if (exists $data->{parameters}) {
        push @params, @{$data->{parameters}};
    }

    die "'source' path evaluates to an empty value" if $source eq '';
    die "'dest' path evaluates to an empty value" if $dest eq '';

    my @cmd = ('rclone', 'sync', $source, $dest);

    if (scalar(@params) > 0) {
        push(@cmd, subst_macros(join(' ', @params)));
    }

    if ($config ne '') {
        push(@cmd, ('--config', $config));
    }

    $self->run_cmd(join(' ', @cmd));
}

1;