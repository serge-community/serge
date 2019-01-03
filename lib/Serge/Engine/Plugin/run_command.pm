package Serge::Engine::Plugin::run_command;
use parent Serge::Engine::Plugin::if;

use strict;
use utf8;

use File::Basename;
use Serge::Util qw(remove_flags set_flag subst_macros);

sub name {
    return 'Run shell command plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        command => {''               => 'LIST',
            '*'                      => 'STRING'
        },

        if => {
            '*' => {
                then => {
                    command => {''   => 'LIST',
                        '*'          => 'STRING'
                    },
                },
            },
        },
    });

    $self->add({
        after_save_localized_file => \&check
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    die "'command' parameter is not specified and no 'if' blocks found" if !exists $self->{data}->{if} && !$self->{data}->{command};

    if (exists $self->{data}->{if}) {
        foreach my $block (@{$self->{data}->{if}}) {
            die "'command' parameter is not specified inside if/then block" if !$block->{then}->{command};
        }
    }
}

sub adjust_phases {
    my ($self, $phases) = @_;

    # remove unused flags added by default by the parent 'if' plugin
    remove_flags($phases, qw(after_load_file after_load_source_file_for_processing before_save_localized_file before_deserialize_ts_file after_serialize_ts_file));

    # always tie to 'after_save_localized_file' phase
    set_flag($phases, 'after_save_localized_file');

    # this plugin makes sense only when applied to a single phase
    # (in addition to 'before_job' phase inherited from Serge::Engine::Plugin::if plugin)
    die "This plugin needs to be attached to only one 'after_save_localized_file' phase" unless @$phases == 2;
}

sub process_then_block {
    my ($self, $phase, $block, $file, $lang, $strref) = @_;

    die "This plugin should only be used in 'after_save_localized_file' phase (current phase: '$phase')" unless $phase eq 'after_save_localized_file';

    my $outfile = $self->{parent}->{engine}->get_full_output_path($file, $lang);
    ($_, my $outpath, $_) = fileparse($outfile); # this way $outpath will include the trailing delimiter

    foreach my $command (@{$block->{command}}) {
        # substitute %FILE% and target language-based macros
        # with the full path to the saved file
        $command = subst_macros($command, $file, $lang);

        # substitute %OUTFILE% macro with the full path to the saved file
        $command =~ s/%OUTFILE%/$outfile/sg;
        # substitute %OUTPATH% macro with the full directory path
        $command =~ s/%OUTPATH%/$outpath/sg;

        die "After macro substitution, 'command' parameter evaluates to an empty string" if $command eq '';

        print "RUN: $command\n";
        system($command);

        my $error_code = unpack 'c', pack 'C', $? >> 8; # error code
        die "Exit code: $error_code\n" if $error_code != 0;
    }

    return (shift @_)->SUPER::process_then_block(@_);
}

sub check {
    my $self = shift;
    return $self->SUPER::check(@_);
}

1;