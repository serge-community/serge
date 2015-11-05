package Serge::Engine::Plugin::append_hint_message;
use parent Serge::Engine::Plugin::if;

use strict;

use Serge::Util qw(set_flag);

sub name {
    return 'Plugin to append extra message to a hint';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        message => {''               => 'LIST',
            '*'                      => 'STRING'
        },

        if => {
            '*' => {
                then => {
                    message => {''   => 'LIST',
                        '*'          => 'STRING'
                    },
                },
            },
        },
    });

    $self->add({
        add_dev_comment => \&add_dev_comment
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    die "'message' parameter is not specified and no 'if' blocks found" if !exists $self->{data}->{if} && !$self->{data}->{message};

    if (exists $self->{data}->{if}) {
        foreach my $block (@{$self->{data}->{if}}) {
            die "'message' parameter is not specified inside if/then block" if !$block->{then}->{message};
        }
    }
}

sub adjust_phases {
    my ($self, $phases) = @_;

    # always tie to 'add_dev_comment' phase
    set_flag($phases, 'add_dev_comment');
}

sub process_then_block {
    my ($self, $phase, $block, $file, $lang, $strref, $commentref, $aref) = @_;

    if ($phase eq 'add_dev_comment') {
        foreach my $message (@{$block->{message}}) {
            push @$aref, $self->{parent}->render_full_output_path($message, $file, $lang);
        }
    }

    return (shift @_)->SUPER::process_then_block(@_);
}

sub add_dev_comment {
    my ($self, $phase, $file, $lang, $strref, $aref) = @_;

    return $self->SUPER::check($phase, $file, $lang, $strref, undef, $aref);
}

1;