package Serge::Importer;
use parent Serge::Engine;

use strict;

use Unicode::Normalize;

use Serge::Util;

sub process_job {
    my ($self, $job) = @_;

    $self->{stats} = {} unless exists $self->{stats};

    $self->init_job($job);
    $self->adjust_job_defaults($job);
    $self->adjust_destination_languages($job);

    # this hash will hold key => {item => <item_id>, string => <string>} mapping
    # for the source resource file
    $job->{source_keys} = {};
    $job->{localized_keys} = {};
    $job->{optimizations} = undef;

    # now that we have a final list of destination languages, we can
    # determine if the job can run or not

    # for import purposes, skip jobs having output_only_mode as well

    if ($self->job_can_run($job) && !$job->{output_only_mode}) {
        print "\n\n*** [".$job->{id}."] ".$job->{name}." ***\n\n";
    } else {
        print "*** SKIPPING: [".$job->{id}."] ".$job->{name}." ***\n";
        return;
    }

    $self->open_database($job);
    $self->adjust_modified_languages($job);

    die "source_dir [$job->{source_dir}] doesn't exist. Try doing an initial data checkout (`serge pull --initialize`), or reconfigure your job" unless -d $job->{source_dir};

    print "Path to source resources: [".$job->{source_dir}."]\n";
    print "Path to localized resources: [".$job->{output_file_path}."]\n";
    print "Languages: [".join(',', sort @{$job->{modified_languages}})."]\n";
    print "DB source: [".$job->{db_source}."]\n";

    # preload all items/strings/translations into cache

    $self->{db}->preload_cache_for_job($job->{db_namespace}, $job->{id}, $job->{modified_languages});

    $self->run_callbacks('before_job');

    $self->run_callbacks('before_update_database_from_source_files');

    $self->{current_lang} = $job->{source_language};

    $self->update_database_from_source_files;

    $self->parse_localized_files;

    # note: do not close the database at this point as it might be reused in another job

    $self->run_callbacks('after_job');

    print "*** [end] ***\n";

}

sub parse_localized_files {
    my ($self) = @_;

    print "\nParsing localized files...\n\n";

    foreach my $file (sort keys %{$self->{files}}) {
        $self->parse_localized_files_for_file($file);
    }
}

sub parse_localized_files_for_file {
    my ($self, $file) = @_;

    $self->{stats}->{$self->{job}->{source_language}} = {} unless exists $self->{stats}->{$self->{job}->{source_language}};
    $self->{stats}->{$self->{job}->{source_language}}->{files}++;

    print "\t$file\n";

    # Setting the global variables

    $self->{current_file_rel} = $file;
    $self->{current_file_id} = $self->{db}->get_file_id($self->{job}->{db_namespace}, $self->{job}->{id}, $self->{current_file_rel}, 1); # do not create

    # sanity check

    die "current_file_id is not defined\n" unless $self->{current_file_id};

    foreach my $lang (@{$self->{job}->{modified_languages}}) {
        $self->parse_localized_files_for_file_lang($file, $lang);
    }

}

sub parse_localized_files_for_file_lang {
    my ($self, $file, $lang) = @_;

    $self->{current_lang} = $lang;

    my $fullpath = $self->get_full_output_path($file, $lang);

    $self->{stats}->{$lang} = {} unless exists $self->{stats}->{$lang};

    $self->{previous_translation} = {};

    # prepare the report cache key
    if ($self->{save_report}) {
        $self->{report} = {} unless exists $self->{report};
        $self->{report}->{$lang} = {} unless exists $self->{report}->{$lang};
        $self->{current_report_key} = $self->{report}->{$lang}->{$file} = [];
    }

    print "\t\t$fullpath\n";

    if (!-f $fullpath) {
        $self->_notice("Missing localized file for '$lang' language", "\t\t\t", 'SERGE_NOTICE_FILE_MISSING');
        return;
    }

    $self->{stats}->{$lang}->{files}++;

    # Getting plugin object

    my ($src) = $self->read_file($fullpath);

    # clear disambiguation cache
    $self->clear_disambiguation_cache();

    # Parsing the file
    eval {
        $self->{job}->{parser_object}->{import_mode} = 1;
        $self->{job}->{parser_object}->parse(\$src, sub { $self->parse_localized_file_callback(@_) }, $lang);
    };

    if ($@) {
        $self->_error("File parsing failed; the file will not be processed in full; reason: $@", "\t\t\t", 1, 'SERGE_ERROR_PARSING_FAILED', '', $lang); # non-fatal
    }
}

sub disambiguate_key {
    my ($self, $store, $key) = @_;

    if (exists $store->{$key}) {
        die "Shouldn't disambiguate when disambiguate_keys is not enabled" unless $self->{disambiguate_keys};

        my $n = 1;
        my $base_key = $key;
        do {
            $n++;
            $key = "$base_key.$n";
        } while exists $store->{$key};
    }

    return $key;
}

sub parse_source_file_callback {
    my ($self, $string, $context, $hint, $flagsref, $lang, $key) = @_;

    if ($key eq '' && !$self->{disambiguate_keys}) {
        $self->_error("Parser plugin didn't provide a key value in a callback. ".
        "Importing translations with this plugin is not possible, unless you use `--disambiguate-keys` option.", "\t\t\t", '', $key, $string, '', $lang);
    }

    if ($string eq '') {
        $self->_notice("Source string for key '$key' is blank, skipping [$lang]", "\t\t", 'SERGE_NOTICE_EMPTY_SOURCE', $key);
        return;
    }

    my $keys = $self->{job}->{source_keys}->{$self->{current_file_rel}};
    $keys = $self->{job}->{source_keys}->{$self->{current_file_rel}} = {} unless defined $keys;

    if (exists $keys->{$key}) {
        if ($self->{disambiguate_keys}) {
            my $orig_key = $key;
            $key = $self->disambiguate_key($keys, $key);
            $self->_notice("Duplicate key '$orig_key' found in source file, changed to '$key' [$lang]", "\t\t\t", 'SERGE_NOTICE_DUPLICATE_KEY', $key, $string, '', $lang);
        } else {
            $self->_error("Duplicate key '$key' found in source file [$lang]", "\t\t\t", 1, 'SERGE_ERROR_DUPLICATE_KEY', $key, $string, '', $lang); # non-fatal
        }
    }

    print "\t\t\t::source file: '$key' => '$string'\n" if $self->{debug};

    my $item_id;
    if ($self->{dry_run}) {
        $string = NFC($string) if ($string =~ m/[^\x00-\x7F]/);
    } else {
        $item_id = Serge::Engine::parse_source_file_callback(@_);
    }
    $keys->{$key} = {item => $item_id, string => $string};
}

sub parse_localized_file_callback {
    my ($self, $translation, $context, $hint, $flagsref, $lang, $key) = @_;

    # Normalize parameters

    $translation = NFC($translation) if ($translation =~ m/[^\x00-\x7F]/);

    my $keys = $self->{job}->{localized_keys};

    $keys->{$self->{current_file_rel}} = {} unless exists $keys->{$self->{current_file_rel}};
    $keys = $keys->{$self->{current_file_rel}};
    $keys->{$lang} = {} unless exists $keys->{$lang};
    $keys = $keys->{$lang};

    if (exists $keys->{$key}) {
        if ($self->{disambiguate_keys}) {
            my $orig_key = $key;
            $key = $self->disambiguate_key($keys, $key);
            $self->_notice("Duplicate key '$orig_key' found in localized file [$lang], changed to '$key'", "\t\t\t");
        } else {
            my $data = $self->{job}->{source_keys}->{$self->{current_file_rel}}->{$key};
            my $source = '';
            $source = $data->{string} if $data;

            if ($translation eq $self->{previous_translation}->{$key}) {
                $self->_warning("Duplicate key '$key' with the same translation found in localized file [$lang]", "\t\t\t", 'SERGE_WARNING_DUPLICATE_KEY', $key, $source, $translation, $lang);
            } else {
                $self->_error("Duplicate key '$key' with different translations found in localized file [$lang]", "\t\t\t", 1, 'SERGE_ERROR_MULTIPLE_TRANSLATIONS', $key, $source); # non-fatal
            }

            return $translation;
        }
    }

    # mark the key name as used for disambiguation to work
    $keys->{$key} = 1;

    # store previous translation to check for multiple translations of the same key
    $self->{previous_translation}->{$key} = $translation;

    # check the resulting key against the store of source keys

    my $data = $self->{job}->{source_keys}->{$self->{current_file_rel}}->{$key};

    if (!$data) {
        $self->_warning("Unknown key '$key' [$lang]", "\t\t\t", 'SERGE_WARNING_UNKNOWN_KEY', $key, '', $translation, $lang);

        return $translation;
    }

    my $item_id = $data->{item};

    if (($translation eq '') && ($data->{string} ne '')) {
        $self->_notice("Translation for key '$key' is blank, skipping [$lang]", "\t\t\t", 'SERGE_NOTICE_EMPTY_TRANSLATION', $key);
        return;
    }

    if ($data->{string} ne $translation) {
        $self->_save_report($key, $lang, $data->{string}, $translation);
    } else {
        $self->_notice("Translation is the same as the source for key '$key' [$lang]", "\t\t\t", 'SERGE_NOTICE_SAME_TRANSLATION', $key, $data->{string}, $translation, $lang);
    }

    print "\t\t\t::localized file [$lang]: '$key' => '$translation'\n" if $self->{debug};

    $self->{db}->set_translation($item_id, $lang, $translation, undef, undef, 0) unless $self->{dry_run};

    return $translation;
}

sub _notice {
    my ($self, $s, $indent_prefix, $error_status, $key, $source, $translation, $lang) = @_;

    print $indent_prefix."NOTICE: $s\n";
    $self->{stats}->{$self->{current_lang}}->{notices}++;
    
    $self->_save_report($key, $lang, $source, $translation, 'notice', $error_status);
}

sub _warning {
    my ($self, $s, $indent_prefix, $error_status, $key, $source, $translation, $lang) = @_;

    print $indent_prefix."WARNING: $s\n";
    $self->{stats}->{$self->{current_lang}}->{warnings}++;
    
    $self->_save_report($key, $lang, $source, $translation, 'warning', $error_status);
}

sub _error {
    my ($self, $s, $indent_prefix, $nonfatal, $error_status, $key, $source, $translation, $lang) = @_;

    print $indent_prefix."ERROR: $s\n";
    $self->{stats}->{$self->{current_lang}}->{errors}++;
    
    $self->_save_report($key, $lang, $source, $translation, 'error', $error_status);
    
    exit(1) unless $nonfatal;
}

sub _save_report {
    my ($self, $key, $lang, $source, $translation, $severity, $error_status) = @_;
    
    if (!$self->{save_report}) {
        return;
    }
    
    $self->{report} = {} unless exists $self->{report};
    $self->{report}->{$self->{current_lang}} = {} unless exists $self->{report}->{$self->{current_lang}};
    $self->{report}->{$self->{current_lang}}->{$self->{current_file_rel}} = [] unless exists $self->{report}->{$self->{current_lang}}->{$self->{current_file_rel}};
    $self->{current_report_key} = $self->{report}->{$self->{current_lang}}->{$self->{current_file_rel}};
    
    push @{$self->{current_report_key}}, {
            key => $key,
            lang => $lang,
            source => $source,
            translation => $translation,
            severity => $severity,
            error_status => $error_status
        };
}

1;