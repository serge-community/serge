package Serge::Command::show;
use parent Serge::Command;

use strict;

use Config::Neat::Inheritable;
use Config::Neat::Render;

sub get_commands {
    return {
        show => {
            handler => \&run,
            info => 'Show expanded version of a configuration file',
            need_config => 1,
        },
    }
}

sub run {
    my ($self) = @_;

    my @config_files = $self->{parent}->get_config_files;
    die "Multiple configuration files not allowed\n" unless $#config_files == 0;

    my $cfg = Config::Neat::Inheritable->new();
    my $data = $cfg->parse_file($config_files[0]);

    my $renderer = Config::Neat::Render->new();
    print $renderer->render($data);

    return 0;
}

1;
