package Serge::Command::test_parser;
use parent Serge::Command;

use strict;

no warnings qw(uninitialized);

use Getopt::Long;
use Serge::Util;

sub get_commands {
    return {
        'test-parser' => {handler => \&run, info => 'Test selected parser against a provided file'},
    }
}

sub init {
    my ($self, $command) = @_;

    $self->SUPER::init($command);

    GetOptions(
        "output-mode:s" => \$self->{output_mode},
    ) or die "Failed to parse some command-line parameters.";

    $self->{parser} = shift @ARGV;
    $self->{path} = shift @ARGV;
}

sub validate_data {
    my ($self, $command) = @_;

    $self->SUPER::validate_data($command);

    die "Unknown --output-mode value\n" unless $self->{output_mode} =~ m/^(|dumper)$/;
    die "Please provide the name of the parser as a first argument to the command" unless defined $self->{parser};
    die "Please provide the path to the file as a second argument to the command" unless defined $self->{path};
    die "The provided path doesn't point to a valid file" unless -f $self->{path};
}

sub run {
    my ($self, $command) = @_;

    # Creating dummy engine object

    my $engine = {
        debug => undef,
    };

    # Loading parser plugin

    my $parser;

    eval('use Serge::Engine::Plugin::'.$self->{parser}.'; $parser = Serge::Engine::Plugin::'.$self->{parser}.'->new($engine);');
    ($@) && die "Can't load parser plugin [$self->{parser}]: $@";

    print "Using plugin: ".$parser->name."\n";

    my $src = read_and_normalize_file($self->{path});
    my @data;

    $parser->parse(\$src, sub {
        my @row = @_;
        push @data, \@row;
        return $row[0]; # return original source string as translation (solely for parser debugging purposes)
    });

    my $mode = lc($self->{output_mode});

    if ($mode eq 'dumper') {
        eval 'use Data::Dumper';
        print Dumper(\@data);

    } else {
        eval 'use Config::Neat::Render';
        my $r = Config::Neat::Render->new({
            wrap_width => 256,
            undefined_value => '-',
        });
        print $r->render({ data => \@data });
    }

    return 0;
}

1;