package Serge::Command::test_parser;
use parent Serge::Command, Serge::Interface::PluginHost;

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
        "data-file:s"   => \$self->{data_file},
        "import-mode"   => \$self->{import_mode},
        "output-mode:s" => \$self->{output_mode},
        "as-objects"    => \$self->{as_objects},
    ) or die "Failed to parse some command-line parameters.";

    $self->{parser} = {
        plugin => shift @ARGV
    };

    $self->{path} = shift @ARGV;
}

sub validate_data {
    my ($self, $command) = @_;

    $self->SUPER::validate_data($command);

    die "Unknown --output-mode value\n" unless $self->{output_mode} =~ m/^(|dumper)$/;
    die "Please provide the name of the parser as a first argument to the command" unless defined $self->{parser}->{plugin};
    die "Please provide the path to the file as a second argument to the command" unless defined $self->{path};
    die "The provided path doesn't point to a valid file" unless -f $self->{path};
    die "The provided '--data-file' parameter doesn't point to a valid file" if ($self->{data_file} ne '') && (!-f $self->{data_file});

    if ($self->{data_file} ne '') {
        eval 'use Config::Neat::Inheritable';
        my $c = Config::Neat::Inheritable->new();

        $self->{parser}->{data} = $c->parse_file($self->{data_file});
    }
}

sub run {
    my ($self, $command) = @_;

    # Loading parser plugin

    my $parser = $self->load_plugin_from_node('Serge::Engine::Plugin', $self->{parser});

    print "Using plugin: ".$parser->name."\n";

    my $src = read_and_normalize_file($self->{path});
    my @data;

    $parser->{import_mode} = 1 if $self->{import_mode};
    $parser->parse(\$src, sub {
        my @row = @_;

        if ($self->{as_objects}) {
            push @data, {
                string => $row[0],
                context => $row[1],
                hint => $row[2],
                flagsref => $row[3],
                lang => $row[4],
                key => $row[5],
            };
        } else {
            push @data, \@row;
        }

        return $row[0]; # return original source string as translation (solely for parser debugging purposes)
    });

    my $mode = lc($self->{output_mode});

    if ($mode eq 'dumper') {
        eval 'use Data::Dumper';
        print Dumper(\@data);
    } else {
        eval 'use Config::Neat::Render';
        my @order = qw(string context hint flagsref lang key);
        my $r = Config::Neat::Render->new({
            wrap_width => 256,
            undefined_value => '',
            sort => \@order
        });
        print $r->render({ data => \@data });
    }

    return 0;
}

1;