package Serge::Sync;
use parent Serge::Interface::PluginHost;

use strict;

use utf8;

use File::Spec::Functions qw(rel2abs splitdir);
use Time::HiRes qw(gettimeofday tv_interval);

use Serge::Engine::Processor;
use Serge::Sync::Util;
use Serge::Util qw(subst_macros);

#
# Initialize object
#
sub new {
    my ($class) = @_;

    my $self = {
        debug               => undef, # enable debug output

        debug_echo_commands => undef, # set to 1 to echo system commands about to be executed
        debug_echo_output   => undef, # set to 1 to echo commands' output to be parsed

        no_pull             => undef, # set to 1 to prevent checking out changes from VCS
        no_localize         => undef, # set to 1 to prevent running the actual l10n script and just do VCS checkout/commit
        no_pull_ts          => undef, # set to 1 to prevent executing pull_ts command (syncing changes from external translation service to local translation files)
        no_push_ts          => undef, # set to 1 to prevent updating push_ts command (pushing local translation files to external translation service)
        no_push             => undef, # set to 1 to prevent committing changes back to VCS

        ts                  => undef, # holds TS (translation service) plugin
        vcs                 => undef, # holds VCS (version control system) plugin
    };

    bless $self, $class;

    return $self;
}

sub validate_config {
    my ($self, $config) = @_;

    die "\$config parameter not passed" unless defined $config;
    die "bad config object" unless defined $config->{data};

    if (!$self->{no_pull_ts} || !$self->{no_push_ts}) {
        die "'sync' section missing" unless defined $config->{data}->{sync};
        die "'sync'->'ts' section missing from " unless defined $config->{data}->{sync}->{ts};
    }

    if (!$self->{no_pull} || !$self->{no_push}) {
        die "'sync' section missing" unless defined $config->{data}->{sync};
        die "'sync'->'vcs' not defined" unless defined $config->{data}->{sync}->{vcs};
    }

    if (!$self->{no_localize}) {
        die "'jobs' section missing" unless defined $config->{data}->{jobs};
    }
}

sub reset_counters {
    my ($self) = @_;
    $self->{total_jobs} = 0;
    $self->{skipped_jobs} = 0;
    $self->{failed_jobs} = 0;
}

sub do_sync {
    my ($self, $engine, $config) = @_;

    $self->validate_config($config);
    $self->{config} = $config;

    # initialize translation service plugin (if necessary)

    if (!$self->{no_pull_ts} || !$self->{no_push_ts}) {
        $self->{ts} = $self->load_plugin_from_node(
            'Serge::Sync::Plugin::TranslationService',
            $config->{data}->{sync}->{ts}
        );
        $self->{ts}->{echo_commands} = 1 if $self->{echo_commands};
        $self->{ts}->{echo_output} = 1 if $self->{echo_output};
    }

    # initialize VCS plugin (if necessary)

    if (!$self->{no_pull} || !$self->{no_push  }) {
        $self->{vcs} = $self->load_plugin_from_node(
            'Serge::Sync::Plugin::VCS',
            $config->{data}->{sync}->{vcs}
        );
        $self->{vcs}->{initialize} = 1 if $self->{initialize};
        $self->{vcs}->{echo_commands} = 1 if $self->{echo_commands};
        $self->{vcs}->{echo_output} = 1 if $self->{echo_output};
    }

    # step 1

    if ($self->{no_pull}) {
        print "Skip 'pull' step\n" if $self->{debug};
    } else {
        print "\nUpdating project from VCS...\n\n";

        my $start = [gettimeofday];
        $self->{vcs}->checkout_all;
        print "'pull' step took ", tv_interval($start), " seconds\n";
    }

    # step 2

    if ($self->{no_pull_ts}) {
        print "Skip 'pull_ts' step\n" if $self->{debug};
    } else {
        print "\nPulling translation files from external translation service...\n\n";
        my $start = [gettimeofday];
        $self->{ts}->pull_ts($self->{languages}); # update all languages
        print "'pull-ts' step took ", tv_interval($start), " seconds\n";
    }

    # step 3

    if ($self->{no_localize}) {
        print "Skip 'localize' step\n" if $self->{debug};
    } else {
        print "\nRunning the translation framework...\n\n";
        my $start = [gettimeofday];
        my $processor = Serge::Engine::Processor->new($engine, $config);
        $processor->run();
        print "'localize' step took ", tv_interval($start), " seconds\n";

        $self->{total_jobs} += $processor->{total_jobs};
        $self->{skipped_jobs} += $processor->{skipped_jobs};
        $self->{failed_jobs} += $processor->{failed_jobs};
    }

    # step 4

    if ($self->{no_push_ts}) {
        print "Skip 'push_ts' step\n" if $self->{debug};
    } else {
        print "\nPushing translation files to external translation service...\n\n";
        my $start = [gettimeofday];
        $self->{ts}->push_ts($self->{languages}); # update all languages
        print "'push-ts' step took ", tv_interval($start), " seconds\n";
    }

    # step 5

    if ($self->{no_push}) {
        print "Skip 'push' step\n" if $self->{debug};
    } else {
        print "\nCommitting updated project files back to VCS\n\n";
        my $start = [gettimeofday];
        $self->{vcs}->commit_all($self->{commit_message});
        print "'push' step took ", tv_interval($start), " seconds\n";
    }
}

sub abspath {
    my ($self, $path) = @_;
    die "Config not initialized yet" unless defined $self->{config};
    return $self->{config}->abspath($path);
}

1;