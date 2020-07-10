package Serge::Engine::Plugin::lib;
use parent Serge::Plugin::Base::Callback;

use strict;

use Serge::Util qw(set_flag subst_macros);

sub name {
    return 'Manipulate @INC to include Perl modules from custom folders';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        path => 'ARRAY'
    });

    $self->add({
        after_job => \&after_job
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    die "'path' parameter is not specified" unless exists $self->{data}->{path};

    # save the original @INC
    $self->{orig_inc} = \@INC;

    # prepend @INC with the provided paths;
    # this needs to be done in validate_data (i.e. as early as possible)
    # so that the other plugins can use the new @INC
    map {
        my $path = subst_macros($_);
        $path = $self->{parent}->abspath($path);

        print "Prepending $path to \@INC\n";
        # insert path at the beginning so that modules can be overridden
        unshift @INC, $path;
    } @{$self->{data}->{path}};
}

sub after_job {
    my ($self) = @_;

    print "Restoring original \@INC\n";
    # restore the original @INC
    @INC = @{$self->{orig_inc}};
}

1;