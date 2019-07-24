package Serge::Command::help;
use parent Serge::Command;

use strict;

use Getopt::Long;
use Serge::Pod;
use Serge;
use Serge::Util::Pager;

sub get_commands {
    return {
        '' => {handler => \&show_default_help},
        help => {handler => \&show_help, info => 'Show help on main application and other commands'},
    }
}

sub init {
    my ($self, $command) = @_;

    $self->SUPER::init($command);

    # OS-specific checks

    $self->{browser} = 1 if ($^O eq 'MSWin32');

    my $console;
    GetOptions(
        'console' => \$console,
    ) or die "Failed to parse some command-line parameters.";

    $self->{browser} = undef if $console;
}

sub show_brief_help {
    my ($self, $message) = @_;

    my @commands = sort keys %{$self->{parent}->{commands}};

    print $message ? $message."\n" : "Serge $Serge::VERSION - Free, Open-Source Solution for Continuous Localization\n";
    $self->{parent}->show_synopsis;

    # determine the max size of commands to render second column
    # with their information nicely aligned
    my $max_command_len;
    foreach (@commands) {
        $max_command_len = length($_) if length($_) > $max_command_len;
    }

    print "Available commands:\n";
    foreach (@commands) {
        my $padding = ' ' x ($max_command_len - length($_));
        my $info = $self->{parent}->{commands}->{$_}->{info};
        print "    $_$padding    $info\n" if $_ ne '';
    }
    print "\n";
}

sub show_default_help {
    my ($self, $command) = @_;
    $self->show_brief_help; # with no message

    return 0;
}

sub show_help {
    my ($self, $command) = @_;

    my $help_on_command = shift @ARGV;
    if ($self->{parent}->known_command($help_on_command)) {
        $self->show_help_on_topic($help_on_command eq '' ? 'serge' : "serge-$help_on_command");
    } else {
        $self->show_brief_help("Unknown command: '$help_on_command'");
        return 1;
    }

    return 0;
}

sub show_help_on_topic {
    my ($self, $command) = @_;

    my $pod = Serge::Pod->new();

    if (!$self->{browser} || !$self->show_in_browser($pod->get_html_path($command))) {

        my $podfile = $pod->get_pod_path($command);
        if (!-f $podfile) {
            print "Sorry, but there's no help available for '$command' in '$pod->{root}'\n";
            exit(2);
        }

        my $fh = Serge::Util::Pager::init;
        $pod->print_as_text($podfile, $fh);
        Serge::Util::Pager::close;
    }
}

sub show_in_browser {
    my ($self, $html_file) = @_;

    return undef unless -f $html_file;

    # Windows
    if ($^O eq 'MSWin32') {
        print "MSWin32: executing `$html_file`\n" if $self->{parent}->{debug};
        `$html_file`; # this should open the .html file in the default associated application (typically, browser)
        my $exitcode = $? >> 8;

        print "Exit code: $exitcode\n" if $self->{parent}->{debug};
        return $exitcode == 0;
    }

    return undef;
}


1;