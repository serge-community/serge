package Test::Config;

use parent Serge::Config;

use strict;

use File::Basename;
use File::Spec::Functions qw/catfile rel2abs/;

our $OUTPUT_PATH = './test-output';
our $REFERENCE_OUTPUT_PATH = './reference-output';
our $TS_DIR = './po';
our $DATA_DIR = './localized-resources';
our $DATABASE_DIR = './database';
our $ERRORS_DIR = './errors';


sub output_path {
    my $self = shift;

    return catfile($self->{base_dir}, $OUTPUT_PATH);
}

sub reference_output_path {
    my $self = shift;

    return catfile($self->{base_dir}, $REFERENCE_OUTPUT_PATH);
}

sub ts_path {
    my $self = shift;

    return catfile($self->{base_dir}, $OUTPUT_PATH, $TS_DIR);
}

sub data_path {
    my $self = shift;

    return catfile($self->{base_dir}, $OUTPUT_PATH, $DATA_DIR);
}

sub db_path {
    my $self = shift;

    return catfile($self->{base_dir}, $OUTPUT_PATH, $DATABASE_DIR);
}

sub errors_path {
    my $self = shift;

    return catfile($self->{base_dir}, $OUTPUT_PATH, $ERRORS_DIR);
}

sub reference_db_path {
    my $self = shift;

    return catfile($self->{base_dir}, $REFERENCE_OUTPUT_PATH, $DATABASE_DIR);
}

sub reference_ts_path {
    my $self = shift;

    return catfile($self->{base_dir}, $REFERENCE_OUTPUT_PATH, $TS_DIR);
}

sub reference_data_path {
    my $self = shift;

    return catfile($self->{base_dir}, $REFERENCE_OUTPUT_PATH, $DATA_DIR);
}

sub reference_errors_path {
    my $self = shift;

    return catfile($self->{base_dir}, $REFERENCE_OUTPUT_PATH, $ERRORS_DIR);
}

sub can_dump_db {
    my $self = shift;

    return $self->{data}->{jobs}->[0]->{db_source} ne '';
}

sub db_dump_type {
    my $self = shift;

    return $self->{data}->{jobs}->[0]->{callback_plugins}->{before_db_close}->[0]->{data}->{type};
}

sub output_lang_files {
    my $self = shift;

    return $self->{data}->{jobs}->[0]->{output_lang_files};
}

1;