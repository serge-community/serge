package Serge::Engine::Plugin::process_if;
use parent Serge::Engine::Plugin::if;

use strict;

sub name {
    return 'Allow or disallow processing based on file/lang/content/comment matching conditions';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->add({
        can_process_source_file => \&check,
        can_extract => \&check,
        can_process_ts_file => \&check,
        can_generate_ts_file => \&check,
        can_translate => \&check,
        can_generate_localized_file => \&check,
        can_generate_localized_file_source => \&check,
        can_save_localized_file => \&check,
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    # this plugin makes sense only when there are rules defined
    die "'if' block is missing" unless exists $self->{data}->{if};
    die "'if' block should contain at least one rule defined in it" unless scalar(@{$self->{data}->{if}}) > 0;
}

sub check {
    my $self = shift;
    return $self->SUPER::check(@_);
}

1;