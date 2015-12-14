package Serge::Engine::Plugin::feature_branch;
use parent Serge::Plugin::Base::Callback;

use strict;

no warnings qw(uninitialized);

use Serge::Util qw(generate_hash set_flags);

sub name {
    return 'Extract only strings missing in the master job';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        master_job        => 'STRING',
    });

    $self->add({
        before_job => \&before_job,
        log_translation => \&log_translation,
        get_translation_pre => \&get_translation_pre,
        can_extract => \&can_extract,
    });

    $self->{cache} = {};
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    $self->{master_mode} = $self->{parent}->{id} eq $self->{data}->{master_job};

    die "You must set 'source_path_prefix' parameter for the slave job that uses 'overlay_mode' plugin" if $self->{parent}->{source_path_prefix} eq '' && !$self->{master_mode};
}

sub adjust_phases {
    my ($self, $phases) = @_;

    $self->SUPER::adjust_phases($phases);

    # always tie to these phases
    set_flags($phases, 'before_job', 'can_extract');

    die "This plugin attaches itself to specific phases; please don't specify phases in the configuration file" unless @$phases == 4;
}

#sub get_translation {
#    my ($self, $phase, $string, $context, $namespace, $filepath, $lang, $disallow_similar_lang, $item_id) = @_;
#
#    return ($self->_fake_translate_string($string), undef, undef, $self->{data}->{save_translations}) if $self->is_test_language($lang);
#    return (); # otherwise, return an empty array
#}

sub before_job {
    my ($self, $phase) = @_;

    # preload the list of strings for current namespace and given job id

    my $master_job_id = $self->{data}->{master_job};
    my $engine = $self->{parent}->{engine};

    #$self->{master_mode} = $self->{parent}->{id} eq $master_job_id;

    if ($self->{master_mode}) {
        print "Running overlay_mode plugin in master mode\n" if $self->{debug};

        # initialize engine-wide plugin data structure for the current job
        $engine->{plugin_data} = {} unless exists $engine->{plugin_data};
        $engine->{plugin_data}->{overlay_mode} = {} unless exists $engine->{plugin_data}->{overlay_mode};
        $engine->{plugin_data}->{overlay_mode}->{$master_job_id} = {};
    } else {
        print "Running overlay_mode plugin in slave mode\n" if $self->{debug};

        if (!exists $engine->{plugin_data} ||
            !exists $engine->{plugin_data}->{overlay_mode} ||
            !exists $engine->{plugin_data}->{overlay_mode}->{$master_job_id}) {
            die "Can't run job with overlay_mode plugin in slave mode before (or without) the master job\n";
        }
    }
    $self->{cache} = $engine->{plugin_data}->{overlay_mode}->{$master_job_id};
}

sub log_translation {
    my ($self, $phase, $string, $context, $hint, $flagsref, $lang, $key, $translation) = @_;

    if ($self->{master_mode}) {
        $self->{cache}->{generate_hash($string, $context, $key)} = $translation;
    }
}

sub get_translation_pre {
    my ($self, $phase, $string, $context, $namespace, $filepath, $lang, $disallow_similar_lang, $item_id, $key) = @_;

    return () if $self->{master_mode}; # do nothing in master mode

    # otherwise, return current translation (or undef, if there's no matching translation)
    return $self->{cache}->{generate_hash($string, $context, $key)};
}

sub string_exists {
    my ($self, $stringref, $context, $key) = @_;
    return exists $self->{cache}->{generate_hash($$stringref, $context, $key)};
}

sub can_extract {
    my ($self, $phase, $file, $lang, $stringref, $hintref, $context, $key) = @_;

    # extract everything for master job
    return 1 if $self->{master_mode};

    # otherwise, we're in an overlay job

    # if we're generating localized files, $lang will be set
    return 1 if defined $lang; # extract everything to translate all the strings, not just overlay ones

    # otherwise (when $lang is not set) we're parsing the source file
    return $self->string_exists($stringref, $context, $key) ? 0 : 1; # extract only strings which are missing from the master job
}

1;