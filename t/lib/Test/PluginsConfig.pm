package Test::PluginsConfig;

use parent Serge::Config;

use strict;

use File::Basename;
use File::Spec::Functions qw/catfile rel2abs/;


our $REFERENCE_ERRORS_DIR = './reference-errors';
our $ERRORS_DIR = './errors';

sub errors_path {
    my $self = shift;

    return catfile($self->{base_dir}, $ERRORS_DIR);
}

sub reference_errors_path {
    my $self = shift;

    return catfile($self->{base_dir}, $REFERENCE_ERRORS_DIR);
}

1;