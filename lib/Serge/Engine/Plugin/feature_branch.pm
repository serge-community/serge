package Serge::Engine::Plugin::feature_branch;
use parent Serge::Plugin::Base::Callback;

use strict;

no warnings qw(uninitialized);

use Serge::Util qw(generate_hash set_flags);
use Time::HiRes qw(gettimeofday tv_interval);

sub name {
    return 'Extract only strings missing in the master job';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        master_job => 'STRING',
    });

    $self->add({
        before_job => \&before_job,
        before_generate_localized_files => \&before_generate_localized_files,
        before_save_localized_file => \&before_save_localized_file,
        after_save_localized_file => \&after_save_localized_file,
        can_extract => \&can_extract,
        get_translation_pre => \&get_translation_pre,
        log_translation => \&log_translation,
    });

    $self->{master_translations} = {};
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    $self->{master_mode} = $self->{parent}->{id} eq $self->{data}->{master_job};

    die "You must set 'source_path_prefix' parameter for the slave job that uses 'feature_branch' plugin" if $self->{parent}->{source_path_prefix} eq '' && !$self->{master_mode};
}

sub adjust_phases {
    my ($self, $phases) = @_;

    $self->SUPER::adjust_phases($phases);

    # always tie to these phases
    set_flags($phases,
        'before_job', 'before_generate_localized_files',
        'before_save_localized_file', 'after_save_localized_file',
        'can_extract', 'get_translation_pre', 'log_translation'
    );

    die "This plugin attaches itself to specific phases; please don't specify phases in the configuration file" unless @$phases == 7;
}

sub before_job {
    my ($self, $phase) = @_;

    # preload the list of strings for current namespace and given job id

    my $master_job_id = $self->{data}->{master_job};
    my $engine = $self->{parent}->{engine};

    #$self->{master_mode} = $self->{parent}->{id} eq $master_job_id;

    if ($self->{master_mode}) {
        print "Running feature_branch plugin in master mode\n";

        # initialize engine-wide plugin data structure for the current job
        $engine->{plugin_data} = {} unless exists $engine->{plugin_data};
        $engine->{plugin_data}->{feature_branch} = {} unless exists $engine->{plugin_data}->{feature_branch};
        $self->{master_translations} = $engine->{plugin_data}->{feature_branch}->{$master_job_id} = {};

    } else {
        print "Running feature_branch plugin in slave mode\n";

        if (!exists $engine->{plugin_data} ||
            !exists $engine->{plugin_data}->{feature_branch} ||
            !exists $engine->{plugin_data}->{feature_branch}->{$master_job_id}) {
            die "Can't run job with feature_branch plugin in slave mode before (or without) the master job\n";
        }

        $self->{master_translations} = $engine->{plugin_data}->{feature_branch}->{$master_job_id};
    }
}

sub before_generate_localized_files {
    my ($self) = @_;

    return () unless $self->{master_mode}; # do nothing in slave mode

    # disable optimizations for localized file generation
    # for a master job,  so that master files are always parsed,
    # and their translations are always resolved and stored in
    # `log_translation` phase. Since this is the last step
    # before the job finishes execution, there's no need to restore
    # optimizations mode after, but we still want to preserve
    # optimizations at file saving time, so the original value
    # of the job `optimizations` param is preserved here
    # to be temporarily restored between `before_save_localized_file`
    # and `after_save_localized_file` phases
    $self->{optimizations} = $self->{parent}->{optimizations};
    $self->{parent}->{optimizations} = undef;
}

sub before_save_localized_file {
    my ($self) = @_;

    return () unless $self->{master_mode}; # do nothing in slave mode

    # restore the original value of `optimizations` job config value
    # to avoid saving the localized file if it didin't change
    $self->{parent}->{optimizations} = $self->{optimizations};
}

sub after_save_localized_file {
    my ($self) = @_;

    return () unless $self->{master_mode}; # do nothing in slave mode

    # disable optimizations again
    $self->{parent}->{optimizations} = undef;
}

# Make the key that best describes a given string;
# if the source key is extracted from the file, then use filepath+key+string+context,
# otherwise, use filepath+string+context. This will allow to expose for translation
# strings in feature branches that have the same key in the same file,
# but a different string or context.
sub _make_cache_key {
    my ($self, $lang, $file, $key, $stringref, $context) = @_;
    return $key ne '' ?
        generate_hash($lang, $file, $key, $$stringref, $context) :
        generate_hash($lang, $file, $$stringref, $context);
}

# Remove the virtual prefix to get the 'base' filepath of a given file
# for both master and slave jobs for better file/string alignment.
# Slave jobs are always expected to set a `source_path_prefix`
# to disambiguate file paths between files in branches;
# setting `source_path_prefix` for the master job is optional.
sub _get_base_filepath {
    my ($self, $filepath) = @_;
    my $prefix = $self->{parent}->{source_path_prefix};
    $filepath =~ s/^\Q$prefix\E// if $prefix ne '';
    return $filepath;
}

sub can_extract {
    my ($self, $phase, $filepath, $lang, $stringref, $hintref, $context, $key) = @_;

    # extract everything for a master job
    return 1 if $self->{master_mode};

    # otherwise, we're in a slave job

    # if we're generating localized files, $lang will be set;
    # extract everything to translate all the strings, not just overlay ones
    return 1 if defined $lang;

    # when $lang is not set, this means we're parsing the source file;
    # extract only strings which are missing from the master job
    # so that translation interchange files will contain only these
    # extra overlay strings
    my $base_filepath = $self->_get_base_filepath($filepath);
    my $cache_key = $self->_make_cache_key(undef, $base_filepath, $key, $stringref, $context);
    return exists $self->{master_translations}->{$cache_key} ? 0 : 1;
}

sub get_translation_pre {
    my ($self, $phase, $string, $context, $namespace, $filepath, $lang, $disallow_similar_lang, $item_id, $key) = @_;

    return () if $self->{master_mode}; # do nothing in master mode

    my $base_filepath = $self->_get_base_filepath($filepath);
    my $cache_key = $self->_make_cache_key($lang, $base_filepath, $key, \$string, $context);

    # if the string is not present in the master job, return
    # an empty array, so the translation can be resolved
    # from .po files / plugins / database
    return () unless defined $self->{master_translations}->{$cache_key};

    # otherwise, return the actual translation as not fuzzy,
    # and do not save it do the database
    return ($self->{master_translations}->{$cache_key}, undef, undef, undef)
}

sub log_translation {
    my ($self, $phase, $string, $context, $hint, $flags,
        $lang, $key, $translation, $namespace, $filepath) = @_;

    return () unless $self->{master_mode}; # do nothing in slave mode

    # save master translation into the cache for later exact string retrieval
    # in get_translation_pre()
    my $base_filepath = $self->_get_base_filepath($filepath);
    my $cache_key = $self->_make_cache_key($lang, $base_filepath, $key, \$string, $context);
    $self->{master_translations}->{$cache_key} = $translation;

    # also, save a 'source string exists' flag for can_extract(),
    # where $lang is undefined
    $cache_key = $self->_make_cache_key(undef, $base_filepath, $key, \$string, $context);
    $self->{master_translations}->{$cache_key} = 1;
}

1;