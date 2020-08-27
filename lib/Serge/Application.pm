package Serge::Application;

use strict;

use Cwd;
use File::Basename;
use File::Find qw(find);
use File::Spec::Functions qw(rel2abs catfile);
use Getopt::Long qw(:config no_auto_abbrev no_ignore_case pass_through);
use Serge::Config::Collector;
use Serge;

sub new {
    my ($class) = @_;

    my $self = {};

    $self->{commands} = {};

    bless $self, $class;

    return $self;
}

sub run {
    my ($self) = @_;

    my ($help, $debug, $version);
    my $result = GetOptions(
        'help' => \$help,
        'debug' => \$debug,
        'version' => \$version,
    );

    my $command = shift @ARGV;

    # Set the environment variables for child processes
    # to be able to recognize that they are running
    # from under Serge, and act accordingly.
    $ENV{'SERGE'} = $Serge::VERSION;
    $ENV{'SERGE_DEBUG'} = 1 if $debug;

    # print out version when passing the flag to a bare `serge` command
    if ($version && $command eq '') {
        print "Serge $Serge::VERSION\n";
        exit(0);
    }

    if (!$result) {
        $self->error("Failed to parse some command-line parameters.");
    }

    if ($debug) {
        $self->{debug} = 1;
        eval('use Carp::Always;');
        warn "Hint: please install 'Carp::Always' module to get extended backtrace information on die()\n" if $@;
    }

    # convert --help parameter anywhere in the path
    # to an equivalent of 'serge help <rest of params>'

    unshift @ARGV, 'help' if $help;

    $self->load_command_plugins;

    my $handler = $self->{commands}->{$command};
    if (!$handler) {
        $self->error("Unknown command: $command\n");
    }

    $handler->{plugin}->{debug} = 1 if $debug;

    my @commands = ($command);
    if (exists $handler->{combine_with}) {
        my %combine;
        @combine{@{$handler->{combine_with}}} = @{$handler->{combine_with}};
        while (scalar @ARGV && exists $combine{$ARGV[0]}) {
            push @commands, shift @ARGV;
        }
    }

    eval {
        map {
            $handler->{plugin}->init($_);
        } @commands;
    };
    $self->error($@) if $@;

    if ($handler->{need_config}) {
        eval {
            $self->{config_collector} = Serge::Config::Collector->new(@ARGV);
        };
        if ($@) {
            $self->error($@, 3, 1); # exit code = 3, show no synopsis
        }

        my @a = $self->get_config_files;
        if (scalar @a == 0) {
            $self->error("This command expects configuration files to work against, but none were provided");
        }
    }

    eval {
        map {
            $handler->{plugin}->validate_data($_);
        } @commands;
    };
    $self->error($@) if $@;


    my $funcref = $handler->{handler};
    # run the commands in the context of the plugin object
    return &$funcref($handler->{plugin}, exists $handler->{combine_with} ? \@commands : $command);
}

sub load_command_plugins {
    my ($self) = @_;

    my @plugins;

    # find plugins in the 'Command' subfolder relative to the location of the current file (Application.pm)

    find(sub {
        if(-f $_ && /\.pm$/) {
            $_ =~ s/\.pm$//i;
            push @plugins, $_;
        }
    }, catfile(dirname(rel2abs(__FILE__)), 'Command'));

    foreach my $plugin (@plugins) {
        print "Loading command plugin: $plugin\n" if $self->{debug};

        my $class = 'Serge::Command::'.$plugin;

        my $p;
        eval('use '.$class.'; $p = '.$class.'->new($self);');
        die "Can't create instance for '$class': $@" if $@;

        my $exported_commands = $p->get_commands;
        foreach my $command (keys %$exported_commands) {
            my $handler = $exported_commands->{$command};

            die "Definition for '$command' command already exists" if exists $self->{commands}->{$command};
            die "No 'handler' parameter defined for '$command' command handler" unless exists $handler->{handler};

            $handler->{plugin} = $p;
            $self->{commands}->{$command} = $handler;
        }
    }
}

sub get_config_files {
    my $self = shift;
    return $self->{config_collector}->get_config_files;
}

sub get_config_object {
    my $self = shift;
    return $self->{config_collector}->get_config_object(@_);
}

sub known_command {
    my ($self, $command) = @_;
    return exists $self->{commands}->{$command};
}

sub show_synopsis {
    my ($self) = @_;

    print qq|
Usage:
    serge <command> [command-specific-options] [--debug]

Get help:
    serge help [command]

|;
}

sub error {
    my ($self, $message, $exitstatus, $no_synopsis) = @_;
    $exitstatus = 1 unless defined $exitstatus;
    chomp $message;
    print $message."\n";
    $self->show_synopsis unless $no_synopsis;
    exit($exitstatus);
}

1;
