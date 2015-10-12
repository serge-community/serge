package Test::DB::Dumper;

use strict;

use Config::Neat::Render;
use Config::Neat::Schema;
use Data::Dumper;
use File::Path;
use File::Spec::Functions qw(rel2abs catfile);

our @TABLE_NAMES = qw/files strings items translations properties/;
our $TYPE_NEAT = 'neat';

sub new {
    my ($class, $engine) = @_;

    die "engine not specified" unless $engine;

    my $self = {
        engine => $engine,
        neat_renderer => Config::Neat::Render->new()
    };

    bless($self, $class);
    return $self;
}

sub _render_as_json {
    my ($self, $data, $table_name) = @_;
    return to_json({$table_name => $data}, {pretty => 1, indent_length => 4});
}

sub _render_as_neat {
    my ($self, $data, $table_name) = @_;
    return $self->{neat_renderer}->render({$table_name => $data});
}

sub _save {
    my ($self, $data, $table_name, $type, $path) = @_;

    eval { mkpath($path) };
    die "Couldn't create $path: $@" if $@;

    my $content;
    if ($type eq $TYPE_NEAT) {
        $content = $self->_render_as_neat($data, $table_name);
    } else {
        $content = $self->_render_as_json($data, $table_name);
    }

    my $filename = catfile($path, $table_name);
    open(OUT, ">$filename");
    binmode(OUT, ':unix :utf8');
    print OUT $content;
    close(OUT);
}

sub dump_l10n_tables {
    my ($self, $type, $output_path) = @_;

    print "TEST: dumping the database to $output_path...\n";

    for (@TABLE_NAMES) {
        $self->_save($self->_get_table_dump($_), $_, $type, $output_path);
    }
}

sub _get_table_dump {
    my ($self, $table_name) = @_;

    my $sql = "SELECT * FROM $table_name";

    my $sth = $self->{engine}->{db}->prepare($sql);
    $sth->execute || die $sth->errstr;
    my $ar_all = $sth->fetchall_arrayref();
    $sth->finish;

    return $ar_all;
}

1;