package Serge::Engine::Plugin::Transform::whitespace;
use parent Serge::Engine::Plugin::Base::Transform;

use strict;

sub name {
    return 'Whitespace normalization plugin';
}

sub filter_key {
    my ($self, $s) = @_;

    $s =~ s/\s+/ /sg;
    $s =~ s/^\s+//sg;
    $s =~ s/\s+$//sg;
    return $s;
}

sub transform {
    my ($self, $s) = @_;

    $s =~ s/\s+/ /sg;
    $s =~ s/^\s+//sg;
    $s =~ s/\s+$//sg;
    return $s;
}

1;