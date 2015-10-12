package Serge::Plugin::Base;

use strict;

use Config::Neat::Inheritable 1.204;
use Config::Neat::Schema 1.204;
use Config::Neat::Util 1.204 qw(to_ixhash_recursive);
use File::Spec::Functions qw(rel2abs);
use File::Basename qw(dirname);

sub name {
    return 'Base plugin';
}

sub new {
    my ($class, $parent) = @_;

    die "parent not specified" unless $parent;

    my $self = {
        parent => $parent,
        schema => Config::Neat::Schema->new({}),
    };

    bless($self, $class);

    return $self;
}

sub init {
    my ($self, $data) = @_;

    $self->{data} = $data;
}

sub set_schema {
    my ($self, $schema_data) = @_;

    $self->{schema}->set($schema_data);
}

sub merge_schema {
    my ($self, $merge_data) = @_;

    my $c = Config::Neat::Inheritable->new();

    $self->set_schema($c->merge_data($self->{schema}->{schema}, to_ixhash_recursive($merge_data), dirname(rel2abs($0))));
}

sub validate_data {
    my ($self) = @_;

    print "Validating plugin data\n" if $self->{parent}->{debug};
    $self->{schema}->validate($self->{data}) if exists $self->{data};
}

1;