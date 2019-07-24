package Serge::Engine::Plugin::trademarks;
use parent Serge::Plugin::Base::Callback;

use strict;

use Serge::Util qw(set_flag);

sub name {
    return 'Add "Do not alter trademarks" comment';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        trademarks => 'ARRAY'
    });

    $self->add({
        add_hint => \&add_hint
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    die "'trademarks' parameter is not specified" unless $self->{data}->{trademarks};

    my $e = 'qr/\b(\Q'.join('\E|\Q', @{$self->{data}->{trademarks}}).'\E)\b/';
    $self->{re} = eval($e);
}

sub adjust_phases {
    my ($self, $phases) = @_;

    # always tie to 'add_hint' phase
    set_flag($phases, 'add_hint');
}

sub add_hint {
    my ($self, $phase, $string, $context, $namespace, $filepath, $source_key, $lang, $aref) = @_;

    my %found;
    while ($string =~ m/$self->{re}/sgi) {
        $found{$1} = 1;
    }
    my $s = join(', ', sort keys %found);
    if ($s ne '') {
        push @$aref, "Please do not alter trademarks ($s)";
    }
}

1;