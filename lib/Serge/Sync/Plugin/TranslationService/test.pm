package Serge::Sync::Plugin::TranslationService::test;
use parent Serge::Sync::Plugin::Base::TranslationService, Serge::Interface::SysCmdRunner;

use strict;

use Serge::Util qw(subst_macros);

sub name {
    return 'Test translation server (used for manual testing) synchronization plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{optimizations} = 1; # set to undef to disable optimizations
}

sub print_command {
    my ($self, $command) = @_;

    print "Running '$command'...\n";
    return 1;
}

sub pull_ts {
    my ($self, $langs) = @_;

    return $self->print_command("pull");
}

sub push_ts {
    my ($self, $langs) = @_;

    return $self->print_command("push");
}

1;