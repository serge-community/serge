package Serge::Sync::Plugin::TranslationService::smartcat_v2;
use parent Serge::Sync::Plugin::Base::TranslationService, Serge::Interface::SysCmdRunner;

use strict;

no warnings qw(uninitialized);

use File::Basename;
use File::Spec::Functions qw(rel2abs);
use Serge::Util qw(subst_macros);

sub name {
    return 'Smartcat translation server (https://smartcat.ai/) synchronization plugin (Version 2)';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema(
        {
            base_url    => 'STRING',
            account_id  => 'STRING',
            token       => 'STRING',
            project_id  => 'STRING',
            project_dir => 'STRING',
            pull_params => 'STRING',
            push_params => 'STRING',
            debug       => 'BOOLEAN',
        }
    );
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    eval('use Smartcat::App;');
    die "ERROR: To use smartcat_v2 plugin, please install Smartcat::App module (run 'cpan Smartcat::App')\n" if $@;

    map {
        if (exists $self->{data}->{$_}) {
            $self->{data}->{$_} = subst_macros($self->{data}->{$_});
        }
    } qw(base_url account_id token project_id project_dir debug);

    map {
        die "'$_' parameter not defined" unless defined $self->{data}->{$_};
    } qw(account_id project_id token);

    $self->{data}->{base_url} = 'https://smartcat.ai'
        unless defined $self->{data}->{base_url};

    if ($self->{data}->{project_dir} eq '') {
        $self->determine_project_dir;
    }
}

sub determine_project_dir {
    my ($self) = @_;

    my %job_ts_file_paths;
    $job_ts_file_paths{ $_->{ts_file_path} }++ for @{ $self->{parent}->{config}->{data}->{jobs} };

    my @job_ts_file_paths = keys %job_ts_file_paths;
    if (@job_ts_file_paths > 1) {
        die sprintf(
            "ERROR: Set 'project_dir' parameter explicitly, because there are different 'ts_file_path' values in the config file: %s\n",
            join(", ", map { "'$_'" } @job_ts_file_paths)
        );
    }
    my $ts_file_path = shift @job_ts_file_paths;

    die sprintf(
        "ERROR: 'ts_file_path' job parameter (%s) doesn't have a '%%LANG%%' or '%%LOCALE%%' macro in it.\n",
        $ts_file_path
    ) unless $ts_file_path =~ m/(%LOCALE%|%LANG%).*\.po/;

    $self->{data}->{project_dir} =
        dirname(dirname($ts_file_path));
}

sub run_smartcat_cli {
    my ($self, $params, $langs) = @_;

    # Note: $langs can be passed down from
    # `serge pull-ts --lang=xx,yy,xx` and
    # `serge push-ts --lang=xx,yy,xx`,
    # but currently smartcat-cli doesn't support
    # specifying a subset of languages to work on.

    $params .=
        ' --base-url=' . $self->{data}->{base_url} .
        ' --token-id=' . $self->{data}->{account_id} . # smarcat-cli uses 'token-id' instead of 'account-id'
        ' --token=' . $self->{data}->{token} .
        ' --project-id=' . $self->{data}->{project_id} .
        ' --project-workdir="' . $self->{data}->{project_dir} . '"';

    $params .= ' --debug' if $self->{data}->{debug};

    return $self->run_cmd('smartcat-cli ' . $params);
}

sub strip_sensitive_info {
    my ($self, $command) = @_;

    $command =~ s/(\-\-token=\").+?(\")/$1******$2/;
    $command =~ s/(\-\-token=).+?(\s)/$1******$2/ unless $1;

    return $command;
}

sub pull_ts {
    my ($self, $langs) = @_;

    my $dir = $self->{data}->{project_dir};
    if (!-d $dir) {
        print "'project_dir' ($dir) does not exist. Run `serge localize` first.\n";
        return;
    }

    my $params = 'pull --skip-missing';
    if ($self->{data}->{pull_params} ne '') {
        $params .= ' ' . $self->{data}->{pull_params};
    }
    return $self->run_smartcat_cli($params, $langs);
}

sub push_ts {
    my ($self, $langs) = @_;

    my $dir = $self->{data}->{project_dir};
    if (!-d $dir) {
        print "'project_dir' ($dir) does not exist. Run `serge localize` first.\n";
        return;
    }

    my $params = 'push --disassemble-algorithm-name="Serge.io PO" --delete-not-existing';
    if ($self->{data}->{push_params} ne '') {
        $params .= ' ' . $self->{data}->{push_params};
    }
    return $self->run_smartcat_cli($params, $langs);
}

1;
