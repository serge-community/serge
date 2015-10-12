package Serge::Engine::Plugin::parse_bypass;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

sub name {
    return 'Bypass parser plugin (returns original text)';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;
    return $lang ? $$textref : undef;
}

1;