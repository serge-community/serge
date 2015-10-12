package Serge::Engine::Plugin::Base::Transform;

use strict;

sub name {
    return 'Base string transformation plugin';
}

sub new {
    my ($class) = @_;

    my $self = {};

    bless($self, $class);

    $self->init;

    return $self;
}

# virtual method
sub init {}

# virtual method
# remove all non-relevant characters that should not be included
# in key comparison
sub filter_key {
    my ($self, $s) = @_;
    return $s;
}

# virtual method
# transform string `$s` based on optionally provided `$target` string
sub transform {
    my ($self, $s, $target) = @_;
    return $s;
}

1; # return true