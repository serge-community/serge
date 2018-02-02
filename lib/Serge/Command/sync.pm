package Serge::Command::sync;
use parent Serge::Command;

use strict;

use Getopt::Long;

use Serge::Config;
use Serge::Engine;
use Serge::Engine::Processor;
use Serge::Sync;

sub get_commands {
    return {
        pull      => {need_config => 1, handler => \&run, info => 'Pull project files from source control', combine_with => [        'push', 'pull-ts', 'push-ts', 'localize']},
        push      => {need_config => 1, handler => \&run, info => 'Push project files to source control',   combine_with => ['pull',         'pull-ts', 'push-ts', 'localize']},
        'pull-ts' => {need_config => 1, handler => \&run, info => 'Pull data from translation server',      combine_with => ['pull', 'push',            'push-ts', 'localize']},
        'push-ts' => {need_config => 1, handler => \&run, info => 'Push data to translation server',        combine_with => ['pull', 'push', 'pull-ts',            'localize']},
        localize  => {need_config => 1, handler => \&run, info => 'Perform localization cycle',             combine_with => ['pull', 'push', 'pull-ts', 'push-ts'            ]},
        sync      => {need_config => 1, handler => \&run, info => 'Perform a full synchronization + localization cycle'},
    }
}

sub init {
    my ($self, $command) = @_;

    $self->SUPER::init(@_);

    my $error_msg = "Failed to parse some command-line parameters.";

    if ($command eq 'pull') {
        GetOptions(
            "initialize"    => \$self->{initialize},
        ) or die $error_msg;
    }

    if ($command =~ m/^(pull-ts|localize|push-ts|sync)$/) {
        GetOptions(
            "force"         => \$self->{force},
            "lang|language|languages=s" => \$self->{languages},
        ) or die $error_msg;
    }

    if ($command =~ m/^(pull|pull-ts|push-ts|push|sync)$/) {
        GetOptions(
            "echo-commands" => \$self->{echo_commands},
            "echo-output"   => \$self->{echo_output},
        ) or die $error_msg;
    }

    if ($command =~ m/^(push|sync)$/) {
        GetOptions(
            "message=s" => \$self->{message},
        ) or die $error_msg;
    }

    if ($command =~ m/^(localize|sync)$/) {
        GetOptions(
            "job|jobs=s"                => \$self->{jobs},
            "rebuild-ts-files"           => \$self->{rebuild_ts_files},
            "output-only-mode"          => \$self->{output_only_mode},
        ) or die $error_msg;
    }
}

sub run {
    my ($self, $commands_list) = @_;

    # if only one command provided, convert it to an array
    $commands_list = [$commands_list] unless ref($commands_list) eq 'ARRAY';

    my $engine = Serge::Engine->new();
    my $sync = Serge::Sync->new();

    $sync->{debug} = 1 if $self->{parent}->{debug};
    $sync->{initialize} = 1 if $self->{initialize};

    $sync->{optimizations} = undef if $self->{force};

    $sync->{echo_commands} = 1 if $self->{echo_commands};
    $sync->{echo_output} = 1 if $self->{echo_output};
    $sync->{commit_message} = $self->{message};

    $engine->{debug} = 1 if $self->{parent}->{debug};
    $engine->{optimizations} = undef if $self->{force};
    $engine->{rebuild_ts_files} = 1 if $self->{rebuild_ts_files};
    $engine->{output_only_mode} = 1 if $self->{output_only_mode};

    my %limit_languages;
    if ($self->{languages}) {
        my @l = split(/,/, $self->{languages});
        $sync->{languages} = \@l;
        $engine->{limit_destination_languages} = \@l;
        @limit_languages{@l} = @l;
    }

    my %limit_jobs;
    if ($self->{jobs}) {
        my @j = split(/,/, $self->{jobs});
        $engine->{limit_destination_jobs} = \@j;
        @limit_jobs{@j} = @j;
    }

    my ($pull, $pull_ts, $localize, $push_ts, $push);

    map {
        $pull     = 1 if $_ eq 'pull';
        $pull_ts  = 1 if $_ eq 'pull-ts';
        $localize = 1 if $_ eq 'localize';
        $push_ts  = 1 if $_ eq 'push-ts';
        $push     = 1 if $_ eq 'push';

        $pull = $pull_ts = $localize = $push_ts = $push = 1 if $_ eq 'sync';
    } @$commands_list;

    $sync->{no_pull}     = !$pull;
    $sync->{no_pull_ts}  = !$pull_ts;
    $sync->{no_localize} = !$localize;
    $sync->{no_push_ts}  = !$push_ts;
    $sync->{no_push}     = !$push;

    $sync->reset_counters;

    my @confs = $self->{parent}->get_config_files;

    my $total_configs = 0;
    my $failed_configs = 0;

    foreach my $config_file (@confs) {

        print qq{
### $config_file

};

        my $config = $self->{parent}->get_config_object($config_file);
        $config->chdir;

        if ($self->{languages} && !$config->any_language_exists(\%limit_languages)) {
            print "Skip (no target languages)\n";
            next;
        }

        if ($self->{jobs} && !$config->any_job_exists(\%limit_jobs)) {
            print "Skip (no target jobs)\n";
            next;
        }

        $total_configs++;

        eval {
            $sync->do_sync($engine, $config);
        };
        if ($@) {
            print "Exception occurred while processing configuration file: $@\n";
            $failed_configs++;
            next;
        }
    }

    $engine->cleanup;

    my $jobs_plural = $sync->{total_jobs} == 1 ? 'job' : 'jobs';
    my $files_plural = $total_configs == 1 ? 'file' : 'files';
    my $was_plural = $sync->{total_jobs} == 1 ? 'was' : 'were';
    print "\nSync complete. $sync->{total_jobs} $jobs_plural in $total_configs configuration $files_plural $was_plural processed\n";

    if ($failed_configs) {
        my $configs_plural = $failed_configs == 1 ? 'config' : 'configs';
        print "$failed_configs $configs_plural failed to be processed\n";
    }

    if ($sync->{skipped_jobs}) {
        my $jobs_plural = $sync->{skipped_jobs} == 1 ? 'job was' : 'jobs were';
        print "$sync->{skipped_jobs} $jobs_plural skipped due to configuration errors\n";
    }

    if ($sync->{failed_jobs}) {
        my $jobs_plural = $sync->{failed_jobs} == 1 ? 'job' : 'jobs';
        print "$sync->{failed_jobs} $jobs_plural ended abnormally\n";
    }

    # return different codes for errors of different severity
    return 3 if $failed_configs;
    return 2 if $sync->{failed_jobs};
    return 1 if $sync->{skipped_jobs};
    return 0;
}

1;