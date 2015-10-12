package Serge::Command;

use strict;

sub get_commands {
    die "get_commands() method must be redeclared in the ancestor class";

    # Example:
    #
    # return {
    #     foo => {handler => \&run_foo},
    #     bar => {handler => \&run_bar, need_config => 1},
    # }
    #
    # where
    #     need_config: set to true value if the command requires configuration files to run against
    #     handler: code reference to a subroutine that handles the command logic
}

sub new {
    my ($class, $parent) = @_;

    die "parent not specified" unless $parent;

    my $self = {
        parent => $parent
    };

    bless($self, $class);
    return $self;
}

sub init {
    my ($self) = @_;
    # do nothing
}

sub validate_data {
    my ($self) = @_;

    # check if some unparsed --parameters are present in arguments

    my @unknown_params;
    map {
        push @unknown_params, $_ if ($_ =~ m/^--/);
    } @ARGV;

    if (scalar @unknown_params) {
        my $message = join("', '", sort @unknown_params);
        die "Unknown parameters: '$message'\n";
    }
}

1;