package Serge::Plugin::Base::Callback;
use parent Serge::Plugin::Base;

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{callback_map} = {};
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    # check for unknown phase names
    if (exists $self->{data}->{phase}) {
        foreach my $phase (@{$self->{data}->{phase}}) {
            die "Unsupported or unknown phase: '$phase'" unless exists $self->{callback_map}->{$phase};
        }
    }
}

sub clear_callback_map {
    my $self = shift;

    $self->{callback_map} = {};
}

sub get_phases {
    my $self = shift;

    # return all phases plugin can handle
    return keys %{$self->{callback_map}};
}

sub adjust_phases {
    my ($self, $phases) = @_;

    # do not enforce any phases by default
}

sub add {
    my $self = shift;

    if (@_ == 1) {
        my $map = shift;

        die "Not a hash" unless ref($map) eq 'HASH';

        foreach my $phase (keys %$map) {
            die "Hash key is not a scalar" unless ref(\$phase) eq 'SCALAR';
            die "Hash value for key '$key' is not a code reference" unless ref($map->{$phase}) eq 'CODE';

            $self->{callback_map}->{$phase} = $map->{$phase};
        }
    } elsif (@_ == 2) {
        my ($phase, $method) = @_;

        die "First parameter is not a scalar" unless ref(\$phase) eq 'SCALAR';
        die "Second parameter is not a code reference" unless ref($method) eq 'CODE';

        $self->{callback_map}->{$phase} = $method;
    } else {
        die "Only one parameter (HASH) or two parameters (SCALAR, CODE) are allowed";
    }
}

sub callback {
    my ($self, $phase) = @_;
    my $funcref = $self->{callback_map}->{$phase};
    &$funcref(@_) if defined $funcref; # run with the rest of the passed parameters
}

1;