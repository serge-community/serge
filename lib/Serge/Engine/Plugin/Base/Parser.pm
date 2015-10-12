package Serge::Engine::Plugin::Base::Parser;
use parent Serge::Plugin::Base::Callback;

use strict;

# virtual method, implementation must be provided in child classes
sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;
    die "Please define your parse method";
}

1;