package Serge::Sync::Plugin::Base::TranslationService;
use parent Serge::Plugin::Base;

use strict;

sub pull_ts {
    my ($self, $langs) = @_;

    die "Please define your pull_ts method";
}

sub push_ts {
    my ($self, $langs) = @_;

    die "Please define your push_ts method";
}

1;