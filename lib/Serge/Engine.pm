package Serge::Engine;

use strict;

no warnings qw(uninitialized);

use utf8;

use DBI;
use Digest::MD5 qw(md5 md5_hex);
use Encode qw(decode encode_utf8 decode_utf8);
use File::Path;
use File::Basename;
use Time::HiRes qw(gettimeofday tv_interval);
use Unicode::Normalize;

use Serge;
use Serge::DB::Cached;
use Serge::FindFiles;
use Serge::Util;

#
# Initialize object
#
sub new {
    my ($class) = @_;

    my $self = {
        debug => $ENV{CI} ne '', # use debug mode from under CI environment to ensure better coverage
        debug_nosave_ts => undef, # disable generation of translation files
        debug_nosave_loc => undef, # disable generation of localized files

        optimizations => 1, # set to undef to disable optimizations and force generate all files

        # job defaults (can be overridden in a job config)
        active => 1,
        output_lang_files => 1,
        output_encoding => 'UTF-8',
        output_bom => 1,
        reuse_translations => 1,
        reuse_orphaned => 1,
        reuse_as_fuzzy_default => 1,
        reuse_as_fuzzy => [],
        reuse_as_not_fuzzy => [],
        similar_languages => [], # list of rules of how to copy translations between similar languages
        # end of job defaults

        rebuild_ts_files => undef, # disable updates from translation files and force recreate them, in order to push changes from db
        output_only_mode => undef, # force output_only_mode on all jobs

        db => Serge::DB::Cached->new(),
        callback_phases => {},
        job => undef, # holds current job object
        current_file_rel => undef, # holds relative path to the currently processed file
        current_file_id => undef, # holds id of current namespace/path record in [files] table
        current_file_keys => undef, # holds the hash of currently processed keys (strings/contexts)

        # if set to a list reference, will limit the set of languages to process
        limit_destination_languages => undef,

        # if set to a list reference, will limit the set of languages to process
        limit_destination_jobs => undef,

        modified_languages => undef,

        files => {},
        force_flags => {},
        skip_flags => {},
        file_mappings => {},
        found_files => {},

    };

    bless $self, $class;
    return $self;
}

sub run_callbacks {
    my ($self, $phase, @params) = @_;

    return $self->{job}->run_callbacks($phase, @params);
}

sub adjust_destination_languages {
    my ($self, $job) = @_;

    # add source language to the list if `output_default_lang_file` is defined
    if ($job->{output_default_lang_file}) {
        push @{$job->{destination_languages}}, $job->{source_language};
    }

    # deduplicate the list
    my @j = @{$job->{destination_languages}};
    my %job_langs;
    @job_langs{@j} = @j;

    if (defined $self->{limit_destination_languages}) {
        my @l = @{$self->{limit_destination_languages}};
        print "List of destination languages limited to: ".join(',', sort @l)."\n" if $self->{debug};

        my %limit_langs;
        @limit_langs{@l} = @l;

        # delete all languages from job_langs hash if they do not exist in limit_langs
        foreach my $lang (keys %job_langs) {
            delete $job_langs{$lang} unless exists $limit_langs{$lang};
        }
    }

    # update the list with a deduplicated sorted version of it
    my @a = sort keys %job_langs;
    $job->{destination_languages} = \@a;

    if (@{$job->{destination_languages}} == 0) {
        print "List of destination languages is empty\n";
    }
}

sub job_can_run {
    my ($self, $job) = @_;

    if (!$self->{job}->{active}) {
        return undef;
    }

    if (defined $self->{limit_destination_jobs}) {
        my @l = @{$self->{limit_destination_jobs}};
        print "List of destination jobs limited to: ".join(',', sort @l)."\n" if $self->{debug};

        my %limit_jobs;
        @limit_jobs{@l} = @l;

        if (!exists $limit_jobs{$self->{job}->{id}}) {
            return undef;
        }
    }

    return undef if @{$job->{destination_languages}} == 0;

    return 1;
}

sub open_database {
    my ($self, $job) = @_;

    # reuse the previous DB  connection if its parameters weren't changed

    return if
        ($self->{db_source} ne '') &&
        ($self->{db_source} eq $job->{db_source}) &&
        ($self->{db_username} eq $job->{db_username}) &&
        ($self->{db_password} eq $job->{db_password});

    # open the database (this will also close previous connection and commit the transaction, if any)
    $self->{db}->open($job->{db_source}, $job->{db_username}, $job->{db_password});

    $self->{db_source} = $job->{db_source};
    $self->{db_username} = $job->{db_username};
    $self->{db_password} = $job->{db_password};

    # preload all properties into cache

    $self->{db}->preload_properties;
}

sub get_job_hash_key {
    my ($self, $job) = @_;
    return "job-hash:".$job->{db_namespace}.":".$job->{id};
}

sub get_job_plugin_version_key {
    my ($self, $job) = @_;
    return "job-plugin:".$job->{db_namespace}.":".$job->{id};
}

sub get_job_serializer_plugin_version_key {
    my ($self, $job) = @_;
    return "job-serializer-plugin:".$job->{db_namespace}.":".$job->{id};
}

sub get_job_engine_version_key {
    my ($self, $job) = @_;
    return "job-engine:".$job->{db_namespace}.":".$job->{id};
}

sub adjust_job_optimizations {
    my ($self, $job) = @_;

    # Check if optimizations can be applied

    my $opt = $self->{optimizations};

    if ($job->{hash} ne $self->{db}->get_property($self->get_job_hash_key($job))) {
        $opt = undef;
        print "*** OPTIMIZATIONS DISABLED: job definition has changed (or job is ran for the first time) ***\n";
    } elsif ($Serge::VERSION ne $self->{db}->get_property($self->get_job_engine_version_key($job))) {
        $opt = undef;
        print "*** OPTIMIZATIONS DISABLED: engine version has changed ***\n";
    } elsif ($job->{plugin_version} ne $self->{db}->get_property($self->get_job_plugin_version_key($job))) {
        $opt = undef;
        print "*** OPTIMIZATIONS DISABLED: parser plugin version has changed ***\n";
    } elsif ($job->{serializer_version} ne $self->{db}->get_property($self->get_job_serializer_plugin_version_key($job))) {
        $opt = undef;
        print "*** OPTIMIZATIONS DISABLED: serializer plugin version has changed ***\n";
    } elsif ($ENV{L10N_FORCE_GENERATE}) {
        $opt = undef;
        print "*** OPTIMIZATIONS DISABLED: L10N_FORCE_GENERATE is ON ***\n";
    } elsif (exists $self->{optimizations} and !$self->{optimizations}) {
        $opt = undef;
        print "*** OPTIMIZATIONS DISABLED: engine 'optimizations' setting is set to OFF ***\n";
    } elsif (exists $job->{optimizations} and !$job->{optimizations}) {
        $opt = undef;
        print "*** OPTIMIZATIONS DISABLED: per-job preference ***\n";
    }

    $job->{optimizations} = $opt;
}

sub adjust_job_defaults {
    my ($self, $job) = @_;

    map {
        $job->{$_} = $self->{$_} unless exists $job->{$_};
    } qw(
        active
        output_lang_files
        output_encoding
        output_bom
        reuse_translations
        reuse_orphaned
        reuse_as_fuzzy_default
        reuse_as_fuzzy
        reuse_as_not_fuzzy
        similar_languages
    );
}

sub save_job_fingerprints {
    my ($self, $job) = @_;

    $self->{db}->set_property($self->get_job_hash_key($job), $job->{hash});
    $self->{db}->set_property($self->get_job_plugin_version_key($job), $job->{plugin_version}) if $job->{plugin_version};
    $self->{db}->set_property($self->get_job_serializer_plugin_version_key($job), $job->{serializer_version}) if $job->{serializer_version};
    $self->{db}->set_property($self->get_job_engine_version_key($job), $Serge::VERSION);
}

sub adjust_modified_languages {
    my ($self, $job) = @_;

    my @j = @{$job->{destination_languages}};

    if ($job->{optimizations} and defined $self->{modified_languages}) {
        my %job_langs;
        @job_langs{@j} = @j;

        my @l = @{$self->{modified_languages}};
        print "List of modified languages: ".join(',', @l)."\n" if $self->{debug};

        my %mod_langs;
        @mod_langs{@l} = @l;

        # delete all languages from mod_langs hash if they do not exist in job_langs
        foreach my $lang (keys %mod_langs) {
            delete $mod_langs{$lang} unless exists $job_langs{$lang};
        }

        my @a = sort keys %mod_langs;
        $job->{modified_languages} = \@a;
    } else {
        # if the configuration parameter is not set, all target languages are considered as modified
        print "*** Will use the full list of destination languages\n" if $self->{debug};
        $job->{modified_languages} = \@j;
    }
}

sub init_job {
    my ($self, $job) = @_;

    # freeze job hash prior to doing any modifications to job structure

    $job->{hash} = $job->get_hash;

    # Initialize temporary job-scope hash of the processed files,
    # to use later when generating localized versions of the files

    $self->{files} = {};
    $self->{src_hash} = {};
    $self->{force_flags} = {};
    $self->{skip_flags} = {};

    # reset an array of found files

    $self->{file_mappings} = {};
    $self->{found_files} = [];

    # reset per-po item count mappings
    # (needed for plugins like `completeness`)

    $self->{ts_items_count} = {};

    # reset cache

    $self->{full_output_path_cache} = {};

    # add reference to current job

    $self->{job} = $job;

    $job->{debug} = $job->{debug} || $self->{debug};

    if (exists $job->{debug_nosave}) {
        $self->{debug_nosave_loc} = $self->{debug_nosave_ts} = $job->{debug_nosave};
    }

    # if output_only_mode flag is set, force it on the job

    $job->{output_only_mode} = 1 if $self->{output_only_mode};

    # preserve the original list for future reference
    $job->{original_destination_languages} = $job->{destination_languages};
}

sub process_job {
    my ($self, $job) = @_;

    $self->init_job($job);
    $self->adjust_job_defaults($job);
    $self->adjust_destination_languages($job);

    # now that we have a final list of destination languages, we can
    # determine if the job can run or not

    my $heading = '['.$job->{id}.']';
    $heading .= ' "'.$job->{name}.'"' if exists $job->{name};

    if ($self->job_can_run($job)) {
        print "\n\n*** $heading ***\n\n";
    } else {
        print "*** SKIPPING: $heading ***\n";
        return;
    }

    $self->open_database($job);
    $self->adjust_job_optimizations($job);
    $self->adjust_modified_languages($job);

    die "source_dir directory [$job->{source_dir}] doesn't exist. Try doing an initial data checkout (`serge pull --initialize`), or reconfigure your job" unless -d $job->{source_dir};

    print "Source dir: [".$job->{source_dir}."]\n";
    print "DB source: [".$job->{db_source}."]\n";
    print "TS file path: [".$job->{ts_file_path}."]\n";
    if (defined $job->{source_ts_file_path}) {
        print "Source TS file path: [".$job->{source_ts_file_path}."]\n";
    }
    print "Output path: [".$job->{output_file_path}."]\n";
    print "Destination languages: [".join(',', sort @{$job->{destination_languages}})."]\n";
    print "Modified languages: [".join(',', sort @{$job->{modified_languages}})."]\n";

    # preload all items/strings/translations into cache

    $self->{db}->preload_cache_for_job($job->{db_namespace}, $job->{id}, $job->{modified_languages});

    $self->run_callbacks('before_job');

    $self->run_callbacks('before_update_database_from_source_files');

    my $start = [gettimeofday];
    $self->update_database_from_source_files;
    print "update_database_from_source_files() took ", tv_interval($start), " seconds\n";

    # The following callback has been deprecated.
    # See Engine::Job::load_plugin_and_register_callbacks for the deprecation notice
    $self->run_callbacks('before_update_database_from_ts_file');
    # new callback name
    $self->run_callbacks('before_update_database_from_ts_files');

    if (!$self->{rebuild_ts_files} && !$job->{output_only_mode}) {
        $start = [gettimeofday];
        $self->update_database_from_ts_files;
        print "update_database_from_ts_files() took ", tv_interval($start), " seconds\n";
    } else {
        print "Skipping update_database_from_ts_files() step\n";
    }

    $self->run_callbacks('before_generate_ts_files');

    if (!$self->{debug_nosave_ts} && !$job->{output_only_mode}) {
        $start = [gettimeofday];
        $self->generate_ts_files;
        print "generate_ts_files() took ", tv_interval($start), " seconds\n";
    } else {
        print "Skipping generate_ts_files() step\n";
    }

    $self->run_callbacks('before_generate_localized_files');

    if (!$self->{debug_nosave_loc}) {
        $start = [gettimeofday];
        $self->generate_localized_files;
        print "generate_localized_files() took ", tv_interval($start), " seconds\n";
    }

    $self->save_job_fingerprints($job);

    $self->commit_transaction;

    # note: do not close the database at this point as it might be reused in another job

    $self->run_callbacks('after_job');

    print "*** [end] ***\n";
}

sub commit_transaction {
    my ($self) = @_;

    $self->{db}->commit_transaction;
}

sub cleanup {
    my ($self) = @_;

    $self->{db}->close;
}

sub update_database_from_source_files_postcheck_callback {
    my ($self, $file_rel, $fullpath) = @_;

    my ($result) = $self->run_callbacks('rewrite_path', $file_rel);
    $file_rel = $result if $result;

    # save relative=>absolute path mapping
    $self->{file_mappings}->{$file_rel} = $fullpath;

    return $file_rel;
}

sub update_database_from_source_files {
    my ($self) = @_;

    print "\nUpdating database from source files...\n\n";

    # Walk through the given directory and its subdirectories, recursively

    my $start = [gettimeofday];

    print "Scanning directory structure...\n";

    my $ff = Serge::FindFiles->new({
        postcheck_callback => sub { return $self->update_database_from_source_files_postcheck_callback(@_) }
    });
    $ff->{prefix} = $self->{job}->{source_path_prefix} if exists $self->{job}->{source_path_prefix};
    $ff->{process_subdirs} = $self->{job}->{source_process_subdirs};
    $ff->{match} = $self->{job}->{source_match} if exists $self->{job}->{source_match};
    $ff->{exclude} = $self->{job}->{source_exclude} if exists $self->{job}->{source_exclude};
    $ff->{dir_exclude} = $self->{job}->{source_exclude_dirs} if exists $self->{job}->{source_exclude_dirs};

    $ff->find($self->{job}->{source_dir});

    @{$self->{found_files}} = sort keys %{$ff->{found_files}};

    my $end = [gettimeofday];
    my $time = tv_interval($start, $end);
    my $files_found = scalar(@{$self->{found_files}});
    print("Scanned in $time sec, $files_found files match the criteria\n");

    die "No files match the search criteria. Please reconfigure your job" unless $files_found;

    # compare the list with the one in the database and see how many files are new,
    # an how many of them are orphaned (and mark them as such), or remove the orphaned
    # flag if needed

    my $files = $self->{db}->get_all_files_for_job($self->{job}->{db_namespace}, $self->{job}->{id});

    my $new = {};
    my $orphaned = {};
    my $no_longer_orphaned = {};
    my $rename = {};

    foreach my $file_rel (@{$self->{found_files}}) { # process files in sorted order for better reporting
        if (exists $self->{file_mappings}->{$file_rel}) { # because it could have been removed in parse_source_file()
            if (!exists $files->{$file_rel}) {
                $new->{$file_rel} = 1;
            } else {
                if ($files->{$file_rel}->{orphaned} == 1) { # file is currently marked as orphaned
                    $no_longer_orphaned->{$file_rel} = 1;
                }
            }
        }
    }

    foreach my $file_rel (sort keys %$files) { # process files in sorted order for better reporting
        if (!exists $self->{file_mappings}->{$file_rel}) {
            if ($files->{$file_rel}->{orphaned} == 0) { # file is currently not marked as orphaned
                $orphaned->{$file_rel} = 1;
            }
        }
    }

    # now that we have a list of new and orphaned files, see if some orphaned files are actually
    # known ones that were renamed

    if ((scalar keys %$new > 0) && (scalar keys %$orphaned > 0)) {
        # first leave only new/orphaned files with the same file size

        # get file sizes of new files
        my $new_fsize = {};
        foreach my $file_rel (sort keys %$new) {
            my $path = $self->get_full_source_path($file_rel);
            my $size = -s $path;
            $new_fsize->{$size} = [] unless exists $new_fsize->{$size};
            push @{$new_fsize->{$size}}, $file_rel;
        }

        # get file sizes of orphaned files
        my $orphaned_fsize = {};
        foreach my $file_rel (sort keys %$orphaned) {
            my $path = $self->get_full_source_path($file_rel);
            my $size = $self->{db}->get_property("size:$files->{$file_rel}->{id}");
            if (defined $size) {
                $orphaned_fsize->{$size} = [] unless exists $orphaned_fsize->{$size};
                push @{$orphaned_fsize->{$size}}, $file_rel;
            }
        }

        foreach my $size (keys %$new_fsize) {
            if (exists $orphaned_fsize->{$size}) {
                my $md5 = {};
                foreach my $file_rel (@{$new_fsize->{$size}}) {
                    my $path = $self->get_full_source_path($file_rel);
                    # go through new files and calculate their md5 hash;
                    # if there are multiple identical files, the last one will win
                    $md5->{md5_hex(encode_utf8(read_and_normalize_file($path)))} = $file_rel;
                }
                foreach my $file_rel (@{$orphaned_fsize->{$size}}) {
                    my $hash = $self->{db}->get_property("hash:$files->{$file_rel}->{id}");
                    if (defined $hash && exists $md5->{$hash}) {
                        my $new_file_rel = $md5->{$hash};
                        $rename->{$file_rel} = $new_file_rel; # map old file_rel to a new one
                        delete $new->{$new_file_rel};
                        delete $md5->{$hash};
                        delete $orphaned->{$file_rel};
                    }
                }
            }
        }
    }

    # update database for renamed files before we parse files (unless we are in output_only mode)
    # otherwise new entry in database will be crated for the renamed file

    map {
        if (!$self->{job}->{output_only_mode}) {
            print "Changing path property for file [$files->{$_}->{id}] to '$rename->{$_}'\n" if $self->{debug};
            # change path in the database
            $self->{db}->update_file_props($files->{$_}->{id}, {path => $rename->{$_}});
        }
        # change the key in the local files list
        $files->{$rename->{$_}} = $files->{$_};
        delete $files->{$_};

    } keys %$rename;

    # now parse files; during this process, plugins may report that some files
    # should be considered orphaned

    foreach my $file_rel (@{$self->{found_files}}) {
        my $orph = undef;
        $self->parse_source_file($file_rel, \$orph);
        if ($orph) {
            # remove the file from $self->{file_mappings} hash
            delete $self->{file_mappings}->{$file_rel};

            # adjust the list of new/orphaned/non-orphaned files
            # for the script to set props later at once
            delete $new->{$file_rel};
            delete $no_longer_orphaned->{$file_rel};

            if (exists $files->{$file_rel} && $files->{$file_rel}->{orphaned} == 0) {
                $orphaned->{$file_rel} = 1;
            }
        }
    }

    print scalar keys %$new, " files are new, ",
          scalar keys %$orphaned, " were orphaned and ",
          scalar keys %$no_longer_orphaned, " are no longer orphaned since last run\n";
    if (scalar keys %$rename) {
        print "The following files were renamed:\n";
        map {
            print "\t$_ => $rename->{$_}\n";
        } sort keys %$rename;
    }

    # now update orphaned flags in the database (unless we are in output_only mode)

    if (!$self->{job}->{output_only_mode}) {
        map {
            if ($files->{$_}->{orphaned} == 0) {
                print "\tSetting 'orphaned' flag on file $_\n";
                $self->{db}->update_file_props($files->{$_}->{id}, {orphaned => 1}); # mark as orphaned
            }
        } keys %$orphaned;

        map {
            if ($files->{$_}->{orphaned} == 1) {
                print "\tRemoving 'orphaned' flag from file $_\n";
                $self->{db}->update_file_props($files->{$_}->{id}, {orphaned => 0}); # mark as not orphaned
            }
        } keys %$no_longer_orphaned;
    }
}

sub parse_source_file {
    my ($self, $file_rel, $orphanedref) = @_;

    # set global CURRENT_FILE_REL variable to current relative file path
    # as it will later be used in different parts
    $self->{current_file_rel} = $file_rel;
    $self->{current_file_id} = undef;

    print "\t$self->{current_file_rel}\n";

    my $path = $self->get_full_source_path($self->{current_file_rel});

    my ($src, $file_hash) = $self->read_file($path, 1);

    $self->run_callbacks('after_load_source_file_for_processing', $self->{current_file_rel}, \$src);

    my $result = combine_and($self->run_callbacks('is_file_orphaned', $self->{current_file_rel}));
    if ($result eq '1') {
        print "\tSkip $self->{current_file_rel} because callback said it is orphaned\n" if $self->{debug};
        $$orphanedref = 1;
        return;
    }

    $result = combine_and(1, $self->run_callbacks('can_process_source_file', $self->{current_file_rel}, undef, \$src));
    if ($result eq '0') {
        print "\tSkip $self->{current_file_rel} because at least one callback returned 0\n" if $self->{debug};
        return;
    }

    # get the file id
    # - in regular mode, create the record in [files] table if it doesn't exist yet
    # - in output_only_mode, don't create a file record if it doesn't exist, but skip the file entirely

    $self->{current_file_id} = $self->{db}->get_file_id($self->{job}->{db_namespace}, $self->{job}->{id}, $self->{current_file_rel}, $self->{job}->{output_only_mode});
    if ($self->{job}->{output_only_mode} && !$self->{current_file_id}) {
        print "\tWARNING: $self->{current_file_rel} will be skipped in 'output_only_mode' because it is not registered in the database\n";
        return;
    }

    # in output_only_mode, check that the file was previously properly parsed.
    # If it wasn't, don't add it to the list of files to process

    if ($self->{job}->{output_only_mode} && $self->{db}->get_property("source:$self->{current_file_id}") eq '') {
        print "\tWARNING: $self->{current_file_rel} will be skipped in 'output_only_mode' because it was not properly parsed previously\n";
        return;
    }

    # Create a temporary array for the file to store item_id's
    # (it will be needed to place strings in translation files in the same order
    # as they were found in the source files)
    my $aref = [];

    # register the file in the list of of ones that need to be processed this time
    $self->{files}->{$self->{current_file_rel}} = $aref;

    my $current_hash = generate_hash($src);

    # store actual src hash in memory so that it can be used in
    # generate_localized_files_for_file_lang() function in output-only mode
    # (where we can't read this value from 'source:<file_id>' property)
    $self->{src_hash}->{$self->{current_file_rel}} = $current_hash;

    if ($self->{job}->{optimizations} and ($current_hash eq $self->{db}->get_property("source:$self->{current_file_id}"))) {
        my $items_text = $self->{db}->get_property("items:$self->{current_file_id}");
        # $items_text can be an empty string, which is fine
        # (this means that the file currently contains no translatable strings)
        if (defined $items_text) {
            @$aref = split(',', $items_text); # restore items
            print "\tSkip parsing $self->{current_file_rel} because it is not modified since last run\n" if $self->{debug};
            # mark file as skipped to optimize po/target file generation
            $self->{skip_flags}->{$self->{current_file_rel}} = 1; # we use filename here, not id
            return;
        }
    }

    # Skip parsing source file if we are in special output_only_mode
    # the file should have been processed by some previous job.
    # Also, if job ID differs, the file's job won't be updated in the database

    return if $self->{job}->{output_only_mode};

    # Update job for the file if necessary (but not for jobs in output_only_mode)

    my $props = $self->{db}->get_file_props($self->{current_file_id});
    if ($self->{job}->{id} ne $props->{job}) {
        print "Setting $self->{current_file_rel} file's job to '".$self->{job}->{id}."'\n";# if $self->{debug};
        $self->{db}->update_file_props($self->{current_file_id}, {job => $self->{job}->{id}});
    }

    $self->clear_disambiguation_cache;

    # Parsing the file

    eval {
        $self->{job}->{parser_object}->parse(\$src, sub { $self->parse_source_file_callback(@_) });
    };

    if ($@) {
        print "\t\tWARNING: File parsing failed; the file will not be processed\n";
        print "\t\tReason: $@\n";

        # Removing the file from the list of ones that need to be processed this time
        delete $self->{files}->{$self->{current_file_rel}};

        return undef;
    }

    # Comparing old item_id's in database with the list of new ones,
    # to set or remove their 'orphaned' flags if necessary

    my %db_items = %{$self->{db}->get_all_items_for_file($self->{current_file_id})};

    foreach my $item_id (@$aref) {
        if ($db_items{$item_id} == 1) { # item is currently marked as orphaned
            $self->{db}->update_item_props($item_id, {orphaned => 0}); # mark as not orphaned
        }
        delete $db_items{$item_id}; # remove from the hash
    }

    # now the hash contains only orphaned items, so mark them as such when needed

    foreach my $item_id (keys %db_items) {
        if ($db_items{$item_id} == 0) { # item is currently not marked as orphaned
            $self->{db}->update_item_props($item_id, {orphaned => 1}); # mark as orphaned
        }
    }

    $self->{db}->set_property("source:$self->{current_file_id}", $current_hash);
    $self->{db}->set_property("hash:$self->{current_file_id}", $file_hash);
    $self->{db}->set_property("size:$self->{current_file_id}", -s $path);
    $self->{db}->set_property("items:$self->{current_file_id}", join(',', @$aref));
}

sub read_file {
    my ($self, $fname, $calc_hash) = @_;

    my $data = read_and_normalize_file($fname);

    my $hash = md5_hex(encode_utf8($data)) if $calc_hash;

    $self->run_callbacks('after_load_file', $fname, $self->{job}->{source_language}, \$data);

    return ($data, $hash);
}

sub clear_disambiguation_cache {
    my ($self) = @_;

    # empty hash of items used to detect duplicate strings in currently parsed file
    $self->{current_file_source_keys} = {};
    $self->{current_file_keys} = {};
}

sub disambiguate_string {
    my ($self, $string, $context, $source_key, $hint) = @_;

    if (defined $source_key) {
        if ($self->{current_file_source_keys}->{$source_key}) {
            print "\t\tWARNING: Duplicate key '$source_key' found in the file\n";
        }
        $self->{current_file_source_keys}->{$source_key} = 1;
    }

    # see if the item was already found in this file and
    # alter context if necessary to disambiguate the string

    my $key = generate_key($string, $context);

    # check if the potential context already exists, and if yes, use source_key as a context

    if ((exists $self->{current_file_keys}->{$key}) && $source_key ne '') {
        $context = $source_key;
        $key = generate_key($string, $context);
    }

    # check if the potential context already exists, and if yes, use hint as a context

    if ((exists $self->{current_file_keys}->{$key}) && $hint ne '') {
        $context = $hint;
        $key = generate_key($string, $context);
    }

    # check if potential context exists, and if yes, try to auto-generate context

    my $context_counter = 1;
    my $context_base = $context || 'context';
    while (exists $self->{current_file_keys}->{$key}) {
        $context = "$context_base.$context_counter";
        $key = generate_key($string, $context);
        $context_counter++;
    }

    $self->{current_file_keys}->{$key} = $source_key;

    return $context;
}

sub parse_source_file_callback {
    my ($self, $string, $context, $hint, $flagsref, $lang, $key) = @_;

    # Normalize parameters

    my $norm = $self->{job}->{normalize_strings};
    $norm = undef if is_flag_set($flagsref, 'dont-normalize');
    $norm = 1 if is_flag_set($flagsref, 'normalize');

    if ($norm) {
        normalize_strref(\$string);
    }

    if ($string eq '') {
        print "::skipping empty string\n" if $self->{debug};
        return;
    }

    $string = NFC($string) if ($string =~ m/[^\x00-\x7F]/);
    $context = NFC($context) if ($context =~ m/[^\x00-\x7F]/);
    $hint = NFC($hint) if ($hint =~ m/[^\x00-\x7F]/);

    $self->run_callbacks('rewrite_source', $self->{current_file_rel}, undef, \$string, \$hint);

    # normalize once again, in case the string was changed
    $string = NFC($string) if ($string =~ m/[^\x00-\x7F]/);

    $context = $self->disambiguate_string($string, $context, $key, $hint);

    my $result = combine_and(1, $self->run_callbacks('can_extract', $self->{current_file_rel}, undef, \$string, \$hint, $context, $key));
    if ($result eq '0') {
        print "\t\tSkip extracting string '$string' because at least one callback returned 0\n" if $self->{debug};
        return;
    }

    my $string_id = $self->{db}->get_string_id($string, $context);

    # get (and create if necessary) the item record for given file_id/string_id

    my $item_id = $self->{db}->get_item_id($self->{current_file_id}, $string_id, $hint);

    print "::[$item_id]::[$self->{current_file_rel}]::[$string],[$context],[$hint],[$lang]\n" if $self->{debug};

    # push the id to the end of the temporary array
    # (we need to record items for all strings, even skipped, to correctly
    # distinguish between orphaned items and existing items pointing to skipped strings)

    push @{$self->{files}->{$self->{current_file_rel}}}, $item_id;

    # get old item hint

    my $props = $self->{db}->get_item_props($item_id);

    # update item with the hint if it is changed

    if ($hint ne $props->{hint}) {
        print "Hint changed for item $item_id: was '$props->{hint}', now '$hint'\n" if $self->{debug};
        $self->{db}->update_item_props($item_id, {hint => $hint});
    }

    # return registered item id (this is used in Serge::Engine method descendant, Serge::Importer)
    return $item_id;
}

sub update_database_from_ts_files {
    my ($self) = @_;

    # Skip parsing translation files if we are in special output_only_mode

    return if $self->{job}->{output_only_mode};

    # Iterating through all modified languages
    foreach my $lang (sort @{$self->{job}->{modified_languages}}) {
        $self->update_database_from_ts_files_lang($lang);
    }
}

sub update_database_from_ts_files_lang {
    my ($self, $lang) = @_;

    # sanity check: if this is a source language, do not import anything into database

    return if ($lang eq $self->{job}->{source_language});

    print "Updating database from translation files for [$lang] language...\n";

    # find all translation files in specified directory

    foreach my $file (sort keys %{$self->{files}}) {
        my $count = scalar @{$self->{files}->{$file}};
        if ($count > 0) {
            my $count_prop_key = "ts:$self->{current_file_id}:$lang:count";
            $count = $self->{db}->get_property($count_prop_key) || $count;
        }
        print "[$file]=>[$count]\n" if $self->{debug};
        if ($count > 0) { # we expect strings from translation file
            $self->update_database_from_ts_files_lang_file($lang, $file);
        }
    }
}

sub update_database_from_ts_files_lang_file {
    my ($self, $lang, $relfile) = @_;

    $self->{current_file_rel} = $relfile;
    $self->{current_file_id} = undef;

    my $fullpath = $self->{job}->get_full_ts_file_path($relfile, $lang);

    if (!-f $fullpath) {
        print "\tFile does not exist: $fullpath\n" if $self->{debug};
        return;
    }

    $self->run_callbacks('before_update_database_from_ts_lang_file', $self->{job}->{db_namespace}, $relfile, $lang);

    my $result = combine_and(1, $self->run_callbacks('can_process_ts_file', $relfile, $lang));
    if ($result eq '0') {
        print "\tSkip $fullpath because at least one callback returned 0\n" if $self->{debug};
        return;
    }

    # creating the record in [files] table if it doesn't exist yet

    $self->{current_file_id} = $self->{db}->get_file_id($self->{job}->{db_namespace}, $self->{job}->{id}, $self->{current_file_rel});

    # Reading the entire file

    if (!open(TS, $fullpath)) {
        print "WARNING: Can't read $fullpath: $!\n";
        return;
    }
    binmode(TS);
    my $text = decode_utf8(join('', <TS>));
    close(TS);

    my $current_hash = generate_hash($text);

    if ($self->{job}->{optimizations} and ($current_hash eq $self->{db}->get_property("ts:$self->{current_file_id}:$lang"))) {
        print "\tSkip $fullpath because it is not modified since last run\n" if $self->{debug};
    } else {
        print "\t$fullpath\n";

        # Parsing the file

        my $units;
        eval {
            $units = $self->{job}->{serializer_object}->deserialize(\$text);
        };

        if ($@) {
            print "\t\tWARNING: File deserializing failed; the file will not be processed\n";
            print "\t\tReason: $@\n";
            return undef;
        }

        foreach my $unit (@$units) {
            my $string_id = $self->{db}->get_string_id($unit->{source}, $unit->{context}, 1); # do not create the string, just look if there is one

            # get item_id for current namespace/file and string/context

            my $item_id = $self->{db}->get_item_id($self->{current_file_id}, $string_id, undef, 1); # do not create

            if (!$item_id) {
                print "\t\t? [no item_id for string] $unit->{key}\n";
                next;
            }

            # run plugins that might want to modify translation/comment,
            # or introduce special functionality on top of the default behavior
            # (for example, remove translations or mark strings as skipped based on the special flag or comment)

            my $item_comment;
            $self->run_callbacks('rewrite_parsed_ts_file_item', $relfile, $lang, $item_id,
                \$unit->{source}, $unit->{flags}, \$unit->{target}, \$unit->{comment}, \$unit->{fuzzy}, \$item_comment);
            if (defined $item_comment) { # it can be an empty string
                $item_comment = undef if $item_comment eq ''; # normalize the empty value
                my $item_props = $self->{db}->get_item_props($item_id);
                if ($item_props->{comment} ne $item_comment) {
                    print "\t\t> [$item_id:item_comment] => '$item_comment'\n";
                    $self->{db}->update_item_props($item_id, {comment => $item_comment});
                }
            }

            # sanity check: if the string is marked as skipped, skip the block

            my $props = $self->{db}->get_string_props($string_id);
            if ($props->{skip}) {
                print "\t\t? [string is marked as skipped] $unit->{key}\n";
                next;
            }

            # sanity check: fuzzy flag with empty translation makes no sense

            if ($unit->{target} eq '' && $unit->{fuzzy}) {
                print "\t\t? [empty translation marked as fuzzy] $unit->{key}\n";
                $unit->{fuzzy} = 0; # clear the fuzzy flag
            }

            my $translation_id = $self->{db}->get_translation_id($item_id, $lang, undef, undef, undef, undef, 1); # do not create

            if ($translation_id) {
                my $props = $self->{db}->get_translation_props($translation_id);

                if ($props->{merge}) {
                    $self->{db}->update_translation_props($translation_id, {merge => 0}); # clear merge flag
                    print "\t\t! [ignore:merge] $unit->{key}\n";
                    next;
                }

                next if (($unit->{target} eq $props->{string}) && ($unit->{comment} eq $props->{comment}) && ($unit->{fuzzy} == $props->{fuzzy}));
            }

            # check again if translation or comment is set here,
            # because the values could have been removed in the callback;
            # also, if translation already exists (translation_id is defined),
            # we must update the record as well
            if ($unit->{target} ne '' or $unit->{comment} ne '' or $translation_id) {
                print "\t\t> $unit->{key} => [$item_id/$lang]=[$translation_id]\n";
                $self->{db}->set_translation($item_id, $lang, $unit->{target}, $unit->{fuzzy}, $unit->{comment}, 0);
            }
        } # foreach

        $self->{db}->set_property("ts:$self->{current_file_id}:$lang", $current_hash);
    } # end if

    $self->run_callbacks('after_update_database_from_ts_lang_file', $self->{job}->{db_namespace}, $relfile, $lang);
}

sub get_full_source_path {
    my ($self, $file) = @_;

    # get absolute path based on provided relative path
    my $path = $self->{file_mappings}->{$file};

    return $path;
}

sub get_full_output_path {
    my ($self, $file, $lang, $base_dir) = @_;

    $base_dir = $self->{job}->{output_file_path} unless $base_dir;

    my $key = join("\001", $file, $lang, $base_dir);
    my $fullpath = $self->{full_output_path_cache}->{$key};

    return $fullpath if $fullpath;

    my ($f) = $self->run_callbacks('rewrite_relative_output_file_path', $file, $lang);
    $file = $f if $f;

    $fullpath = $self->{job}->render_full_output_path($base_dir, $file, $lang);

    ($f) = $self->run_callbacks('rewrite_absolute_output_file_path', $fullpath, $lang);
    $fullpath = $f if $f;

    return $self->{full_output_path_cache}->{$key} = $fullpath;
}

# this will save the new fullpath to the cache so that next calls to
# get_full_output_path() will return this value
sub set_full_output_path {
    my ($self, $file, $lang, $fullpath, $base_dir) = @_;

    $base_dir = $self->{job}->{output_file_path} unless $base_dir;

    my $key = join("\001", $file, $lang, $base_dir);
    return $self->{full_output_path_cache}->{$key} = $fullpath;
}

sub generate_ts_files {
    my ($self) = @_;

    # Skip generating translation files if we are in special output_only_mode

    return if $self->{job}->{output_only_mode};

    print "\nGenerating translation files...\n\n";

    foreach my $file (sort keys %{$self->{files}}) {
        $self->generate_ts_files_for_file($file);
    }
}

sub generate_ts_files_for_file {
    my ($self, $file) = @_;

    # Setting the global variables
    $self->{current_file_rel} = $file;
    $self->{current_file_id} = $self->{db}->get_file_id($self->{job}->{db_namespace}, $self->{job}->{id}, $file, 1); # do not create

    my $modified = !exists($self->{skip_flags}->{$file}) || $self->{rebuild_ts_files};

    if ($self->{job}->{optimizations} && !$self->{rebuild_ts_files}) {
        my $reason = $self->{job}->{output_only_mode} ? 'differs from the original version' : 'modified';
        print "\t$file".($modified ? " ($reason)" : ' (not modified)')."\n";
    } else {
        print "\t$file (forced mode)\n";
    }

    # sanity check

    die "ERROR: CURRENT_FILE_ID is not defined\n" unless $self->{current_file_id};

    my $target_langs;
    if (!$modified) {
        print "\t\t*** File wasn't changed, will walk through modified languages only\n" if $self->{debug};
        # note that this doesn't cover situations when there are some new translation files for new languages
        # that need to be generated; however, this should be taken care of in some higher-level logic
        # (i.e. if the job parameters are changed since last run, the full pass with no optimizations
        # should be performed)
        $target_langs = $self->{job}->{modified_languages};
    } else {
        print "\t\t*** File was changed, will walk through all destination languages\n" if $self->{debug};
        $target_langs = $self->{job}->{destination_languages};
    }

    my @target_langs_to_generate = @$target_langs;

    my %target_langs_hash = map {$_ => 1} @target_langs_to_generate;

    if ($self->{job}->{ts_default_lang_file}) {
        if (not exists $target_langs_hash{$self->{job}->{source_language}}) {
            push @target_langs_to_generate, $self->{job}->{source_language};
            $target_langs_hash{$self->{job}->{source_language}} = 1;
        }
    } else {
        # skip generating TS files for source language (it is added in `output_default_lang_file` mode implicitly)
        if (exists $target_langs_hash{$self->{job}->{source_language}}) {
            delete $target_langs_hash{$self->{job}->{source_language}}
        }
    }

    foreach my $lang (@target_langs_to_generate) {
        if (exists $target_langs_hash{$lang}) {
            $self->generate_ts_files_for_file_lang($file, $lang);
        }
    }
}

sub generate_ts_files_for_file_lang {
    my ($self, $file, $lang) = @_;

    my $fullpath = $self->{job}->get_full_ts_file_path($file, $lang);

    my $result = combine_and(1, $self->run_callbacks('can_generate_ts_file', $file, $lang));
    if ($result eq '0') {
        print "\t\tSkip generating $fullpath because at least one callback returned 0\n" if $self->{debug};
        return;
    }

    my $namespace = $self->{job}->{db_namespace};
    my $locale = locale_from_lang($lang);

    my $dir = dirname($fullpath);

    my $aref = $self->{files}->{$file};

    my @units;
    my %processed;
    my $count = 0;

    my $ts_items_count_key = "$self->{current_file_id}:$lang";
    my $count_prop_key = "ts:$self->{current_file_id}:$lang:count";

    # get the highest USN for the current language and all similar languages
    my $current_usn = $self->{db}->get_highest_usn_for_file_lang($self->{current_file_id}, $lang);

    map {
        my $usn = $self->{db}->get_highest_usn_for_file_lang($self->{current_file_id}, $_);
        $current_usn = $usn if $usn > $current_usn;
    } $self->{job}->gather_similar_languages_for_lang($lang);

    my $old_usn = $self->{db}->get_property("usn:$self->{current_file_id}:$lang");

    # regenerate translation file if either:
    # a) optimizations are disabled (job in a forced mode)
    # b) rebuild_ts_files option is turned on
    # c) target file is missing
    # d) translations or items for the file have changed (based on translations' and items' highest usn value)
    my $need_generate_ts_file = !$self->{job}->{optimizations} || $self->{rebuild_ts_files} || !-f $fullpath || ($current_usn ne $old_usn);

    # also, if the translations have changed, set additionally a force flag on a specific file:lang combo
    if ($current_usn ne $old_usn) {
        $self->{force_flags}->{"$self->{current_file_id}.$lang"} = 1;
    }

    if (!$need_generate_ts_file) {
        my $old_ts_items_count = $self->{db}->get_property($count_prop_key);
        if (defined $old_ts_items_count) {
            $self->{ts_items_count}->{$ts_items_count_key} = $old_ts_items_count;
            print "\t\tSkip generating $fullpath: translations didn't change\n" if $self->{debug};
            return;
        }
    }

    foreach my $item_id (@$aref) {

        # .po files do not allow duplicate keys,
        # so skip the keys which were already processed

        if ($processed{$item_id}) {
            print "WARNING: duplicate item id $item_id\n";
            next;
        }

        # Getting the properties of the item and its linked string

        my $item_props = $self->{db}->get_item_props($item_id);
        my $string_id = $item_props->{string_id};
        my $string_props = $self->{db}->get_string_props($string_id);

        # Skip the item if it is marked as skipped
        next if ($string_props->{skip});

        my $string = $string_props->{string};
        my $context = $string_props->{context};
        my $key = generate_key($string, $context);
        my $source_key = $self->{current_file_keys}->{$key};

        my $hint = $item_props->{hint};
        my $item_comment = $item_props->{comment};

        my $result = combine_and(1, $self->run_callbacks('can_translate', $file, $lang, \$string, \$hint));
        if ($result eq '0') {
            print "\t\tSkip publishing string '$string' in translation file because at least one callback returned 0\n" if $self->{debug};
            next;
        }

        # mark the key as processed

        $processed{$item_id} = 1;

        # increment item counter
        $count++;

        # Get translated string; for default language, the returned string will be equal
        # to the original string (i.e. all strings in the default language are already 'translated')

        my ($translation, $fuzzy, $comments) = $self->get_translation($string, $context, $namespace,
            $file, $lang, undef, $item_id, $source_key);

        my @hint_lines;

        push @hint_lines, $hint if ($hint ne '') && ($hint ne $string);

        # run callbacks that might want to modify the hint (developer comment)
        if ($self->{job}->has_callbacks('add_dev_comment')) {
            print "Deprecation notice: add_dev_comment phase is deprecated. Use add_hint phase instead\n";
            $self->run_callbacks('add_dev_comment', $file, $lang, \$string, \@hint_lines);
        } else {
            $self->run_callbacks(
                'add_hint',
                $string, $context, $namespace, $file, $source_key, $lang, \@hint_lines
            );
        }

        if ($item_comment ne '') {
            push @hint_lines, '' if @hint_lines > 0; # add extra line break between hint and extra item comment
            push @hint_lines, $item_comment;
        }

        my $hint = join("\n", @hint_lines);

        # push the unit to the array

        push @units, {
            key => $key,
            source => $string,
            context => $context,
            target => $translation,
            comment => $comments, # translator's comments
            fuzzy => $fuzzy,
            hint => $hint, # developer's comments
        };
    } # foreach key

    # serialize the file

    my $text;
    eval {
        $text = $self->{job}->{serializer_object}->serialize(\@units, $file, $lang);
    };

    if ($@) {
        print "\t\tWARNING: File serializing failed; the file will not be saved\n";
        print "\t\tReason: $@\n";
        return undef;
    }

    # update translation file item counter property

    $self->{ts_items_count}->{$ts_items_count_key} = $count;

    # update translation file item counter in database

    my $old_ts_items_count = $self->{db}->get_property($count_prop_key);
    if ($count ne $old_ts_items_count) {
        $self->{db}->set_property($count_prop_key, $count);
    }

    # checking translation file hash
    my $current_hash = generate_hash($text);
    my $old_hash = $self->{db}->get_property("ts:$self->{current_file_id}:$lang");

    # save translation file if either:
    # a) optimizations are disabled (job in a forced mode)
    # b) rebuild_ts_files option is turned on
    # c) target file is missing
    # d) file hash has changed
    my $need_save_ts_file = !$self->{job}->{optimizations} || $self->{rebuild_ts_files} || !-f $fullpath || ($current_hash ne $old_hash);

    if ($need_save_ts_file) {
        # we need to save even empty translation files with no translatables
        # because otherwise it will lead to stale files with old translatables

        eval { mkpath($dir) };
        die "ERROR: Couldn't create $dir: $@" if $@;

        print "\t\tSaving $fullpath";
        open(TS, ">$fullpath") || die "ERROR: Can't write to [$fullpath]: $!";
        binmode(TS);
        print TS encode_utf8($text); # encode manually to avoid 'Wide character in print' warnings and force Unix-style endings
        close(TS);
        my $size = -s $fullpath;
        print " ($size bytes)\n";
    } else {
        print "\t\tSkip saving $fullpath: content didn't change\n" if $self->{debug};
    }

    # get the highest USN for the current language and all similar languages
    #
    # (we need to do it again because the usn may have been bumped up
    # as some translations may have been saved to the database)
    #
    # NOTE: this is only supposed to work under assumption that no other process
    # writes to the database during TS file generation; otherwise we will be 'forgetting'
    # about all these changes and not pushing them to a TS file on next run
    $current_usn = $self->{db}->get_highest_usn_for_file_lang($self->{current_file_id}, $lang);

    if ($current_usn ne $old_usn) {
        $self->{db}->set_property("usn:$self->{current_file_id}:$lang", $current_usn);
    }
    if ($current_hash ne $old_hash) {
        $self->{db}->set_property("ts:$self->{current_file_id}:$lang", $current_hash);
    }
}

sub generate_localized_files {
    my ($self) = @_;

    return unless $self->{job}->{output_lang_files};

    print "\nGenerating localized files...\n\n";

    foreach my $file (sort keys %{$self->{files}}) {
        $self->generate_localized_files_for_file($file);
    }

    print "\n";
}

sub generate_localized_files_for_file {
    my ($self, $file) = @_;

    # Setting the global variables

    $self->{current_file_rel} = $file;
    $self->{current_file_id} = $self->{db}->get_file_id($self->{job}->{db_namespace}, $self->{job}->{id}, $self->{current_file_rel}, 1); # do not create

    my $modified = !exists $self->{skip_flags}->{$file};

    if ($self->{job}->{optimizations}) {
        my $reason = $self->{job}->{output_only_mode} ? 'differs from the original version' : 'modified';
        print "\t$file".($modified ? " ($reason)" : ' (not modified)')."\n";
    } else {
        print "\t$file (forced mode)\n";
    }

    # sanity check

    die "ERROR: CURRENT_FILE_ID is not defined\n" unless $self->{current_file_id};

    my $target_langs;
    if (!$modified) {
        print "\t\t*** File wasn't changed, will walk through modified languages only\n" if $self->{debug};
        # note that this doesn't cover situations when there are some new localized files for new languages
        # have to be generated; however, this should be taken care of in some higher-level logic
        # (i.e. if the job parameters are changed since last run, the full pass with no optimizations
        # should be performed)
        $target_langs = $self->{job}->{modified_languages};
    } else {
        print "\t\t*** File was changed, will walk through all destination languages\n" if $self->{debug};
        $target_langs = $self->{job}->{destination_languages};
    }

    foreach my $lang (@$target_langs) {
        $self->generate_localized_files_for_file_lang($file, $lang);
    }
}

sub generate_localized_files_for_file_lang {
    my ($self, $file, $lang) = @_;

    my $result = combine_and(1, $self->run_callbacks('can_generate_localized_file', $file, $lang));

    # get full output path only *after* the 'can_generate_localized_file' callbacks has finished,
    # since the path could have been modified there

    my $srcpath = $self->get_full_source_path($file);
    my $fullpath = $self->get_full_output_path($file, $lang);
    my $dir = dirname($fullpath);

    if ($result eq '0') {
        print "\t\tSkip generating $fullpath because at least one callback returned 0\n" if $self->{debug};
        return;
    }

    # Always construct the key with the JOB id to disambiguate the keys from multiple jobs
    # working in output_only_mode and sharing the same namespace

    my $filekey = "$self->{current_file_id}:$self->{job}->{id}";

    my $source_hash = $self->{src_hash}->{$self->{current_file_rel}};
    die "source_hash is undefined" unless $source_hash ne '';
    # for source language we don't parse translation file, so get_property would return an empty string;
    # DB has a constraint: property value should not be empty. So for the source language we return a dummy non-empty string
    my $source_ts_file_hash = ($lang eq $self->{job}->{source_language}) ? '-' : $self->{db}->get_property("ts:$self->{current_file_id}:$lang");

    my $file_exists = -f $fullpath;
    my $current_mtime = file_mtime($fullpath) if $file_exists;
    my $old_mtime = $self->{db}->get_property("target:mtime:$filekey:$lang");

    # the force flag will be absent if the source file was skipped,
    # so there is no need to check the skip flag here; this optimization will
    # work automatically

    if ($self->{force_flags}->{"$self->{current_file_id}.$lang"} == 0) { # if not forced
        if ($self->{job}->{optimizations}
                and $file_exists
                and ($current_mtime eq $old_mtime)
                and ($source_hash eq $self->{db}->get_property("source:$filekey:$lang"))
                and ($source_ts_file_hash eq $self->{db}->get_property("source:ts:$filekey:$lang"))
            ) {
            print "\t\tSkip generating $fullpath because source file and translations did not change, target file exists and has the same modification time\n" if $self->{debug};
            return;
        }
    }

    my ($src) = $self->read_file($srcpath);

    $result = combine_and(1, $self->run_callbacks('can_generate_localized_file_source', $file, $lang, \$src));
    if ($result eq '0') {
        print "\t\tSkip processing $srcpath because at least one callback returned 0\n" if $self->{debug};
        return;
    }

    $self->run_callbacks('after_load_source_file_for_generating', $srcpath, $lang, \$src);

    $self->clear_disambiguation_cache;

    my $out;
    eval {
        $out = $self->{job}->{parser_object}->parse(\$src, sub { $self->generate_localized_files_for_file_lang_callback(@_) }, $lang);
    };

    if ($@) {
        print "\t\tWARNING: Localized file generation failed; the file will not be saved\n";
        print "\t\tReason: $@\n";
        return undef;
    }

    $result = combine_and(1, $self->run_callbacks('can_save_localized_file', $file, $lang, \$out));
    if ($result eq '0') {
        print "\t\tSkip saving $fullpath because at least one callback returned 0\n";# if $self->{debug};
        return;
    }

    $self->run_callbacks('before_save_localized_file', $file, $lang, \$out);

    my $enc = $self->{job}->{output_encoding};
    my $text;

    # print BOM
    if ($self->{job}->{output_bom}) {
        $text = "\xFF\xFE"         if  (uc($enc) eq 'UTF-16LE');
        $text = "\xFE\xFF"         if ((uc($enc) eq 'UTF-16BE') || (uc($enc) eq 'UTF-16'));
        $text = "\xFF\xFE\x00\x00" if  (uc($enc) eq 'UTF-32LE');
        $text = "\x00\x00\xFE\xFF" if ((uc($enc) eq 'UTF-32BE') || (uc($enc) eq 'UTF-32'));
        $text = "\xEF\xBB\xBF"     if  (uc($enc) eq 'UTF-8');
    }

    # append content
    $text .= encode($enc, $out);

    my $current_hash = generate_hash($text);
    my $old_hash = $self->{db}->get_property("target:$filekey:$lang");

    if ($self->{job}->{optimizations}
            and $file_exists
            and ($current_hash eq $old_hash)
            and ($current_mtime eq $old_mtime)) {
        print "\t\tSkip saving $fullpath: content hash and file modification time are the same\n" if $self->{debug};
    } else {
        my @reasons;

        if (!$self->{job}->{optimizations}) {
            push @reasons, 'forced mode is on';
        } else {
            if (!$file_exists) {
                push @reasons, 'file didn\'t exist before';
            } elsif (!$old_hash) {
                push @reasons, 'file was never saved before';
            } else {
                push @reasons, 'content changed' if $current_hash ne $old_hash;
                push @reasons, 'file was modified on disk' if $current_mtime ne $old_mtime;
            }
        }

        eval { mkpath($dir) };
        die "Couldn't create $dir: $@" if $@;

        # Writing the entire file
        print "\t\tSaving $fullpath, because ".join(', ', @reasons);
        open(OUT, ">$fullpath") || die "Can't write to [$fullpath]: $!";
        binmode(OUT);
        print OUT $text;
        close(OUT);
        my $size = -s $fullpath;
        print " ($size bytes)\n";

        $self->run_callbacks('on_localized_file_change', $file, $lang, \$text);

        $self->{db}->set_property("target:$filekey:$lang", $current_hash);
        $self->{db}->set_property("target:mtime:$filekey:$lang", file_mtime($fullpath)); # read mtime again since the file was saved
    }

    # $source_hash and $source_ts_file_hash might be undefined if the translation file has not been parsed or saved yet before
    # (in e.g. `output_only_mode` where we skip saving any translation files)

    $self->{db}->set_property("source:$filekey:$lang", $source_hash) if $source_hash ne '';
    $self->{db}->set_property("source:ts:$filekey:$lang", $source_ts_file_hash) if $source_ts_file_hash ne '';

    $self->run_callbacks('after_save_localized_file', $file, $lang, \$text);
}

sub generate_localized_files_for_file_lang_callback {
    my ($self, $string, $context, $hint, $flagsref, $lang, $key) = @_;

    # Normalize parameters

    my $norm = $self->{job}->{normalize_strings};
    $norm = undef if is_flag_set($flagsref, 'dont-normalize');
    $norm = 1 if is_flag_set($flagsref, 'normalize');

    if ($norm) {
        normalize_strref(\$string);
    }

    if ($string eq '') {
        print "::skipping empty string\n" if $self->{debug};
        return $string;
    }

    $string = NFC($string) if ($string =~ m/[^\x00-\x7F]/);
    $context = NFC($context) if ($context =~ m/[^\x00-\x7F]/);
    $hint = NFC($hint) if ($hint =~ m/[^\x00-\x7F]/);

    $self->run_callbacks('rewrite_source', $self->{current_file_rel}, $lang, \$string, \$hint);

    # normalize once again, in case the string was changed
    $string = NFC($string) if ($string =~ m/[^\x00-\x7F]/);

    $context = $self->disambiguate_string($string, $context, $key, $hint);

    my $result = combine_and(1, $self->run_callbacks('can_extract', $self->{current_file_rel}, $lang, \$string, \$hint, $context, $key));
    if ($result eq '0') {
        print "\t\tSkip extracting string '$string' because at least one callback returned 0\n" if $self->{debug};
        return $self->{job}->{leave_untranslated_blank} ? '' : $string;
    }

    $result = combine_and(1, $self->run_callbacks('can_translate', $self->{current_file_rel}, $lang, \$string, \$hint));
    if ($result eq '0') {
        print "\t\tSkip translating string '$string' because at least one callback returned 0\n" if $self->{debug};
        return $self->{job}->{leave_untranslated_blank} ? '' : $string;
    }

    # get (do not create) the string record for given string/context

    my $string_id = $self->{db}->get_string_id($string, $context, 1); # do not create
    my $item_id = $self->{db}->get_item_id($self->{current_file_id}, $string_id, undef, 1) if $string_id; # do not create

    # sanity checks: the string id and item id should be already defined if we got to this point

    if ((!$string_id || !$item_id) && $self->{job}->{output_only_mode}) {
        print "\t\tWARNING: String '$string' is not registered in the database\n";
    }

    if (!$self->{job}->{output_only_mode}) {
        if (!$string_id) {
            print "\t\t? [string_id] not defined for string='$string', context='$context' (potential problem with the parser?)\n" if $self->{debug};
        } elsif (!$item_id) {
            print "\t\t? [item_id] not defined for string_id $string_id\n" if $self->{debug};
        }
    }

    print "::[$item_id] >> [$self->{current_file_rel}]::[$string], [$context], [$hint], [$lang], [$key]\n" if $self->{debug};

    my ($translation, $fuzzy) = $self->get_translation($string, $context, $self->{job}->{db_namespace}, $self->{current_file_rel}, $lang, undef, $item_id, $key);

    print "::[$item_id] << [$translation, $fuzzy]\n" if $self->{debug};
    if ($translation eq '') {
        $translation = $self->{job}->{leave_untranslated_blank} ? '' : $string;
    }

    if (combine_or($self->run_callbacks('rewrite_translation', $self->{current_file_rel}, $lang, \$translation))) {
        # if any of the rewrite_translation plugins returned a true value, normalize the output
        $translation = '' if !defined $translation; # convert to a string for consistency
        $translation = NFC($translation);
    }

    if (is_flag_set($flagsref, 'pad')) {
        my $n = $flagsref->[get_flag_pos($flagsref, 'pad') + 1]; # get the first param
        $translation = sprintf('%*s', -$n, $translation); # pad with spaces (spaces are appended to the end)
    }

    $self->run_callbacks('log_translation', $string, $context, $hint, $flagsref, $lang, $key, $translation);

    return $translation;
}

sub get_translation { # either from cache or from database
    my ($self, $string, $context, $namespace, $filepath, $lang, $disallow_similar_lang, $item_id, $key) = @_;

    # For source language, return the original string immediately ("exact match")

    if ($lang eq $self->{job}->{source_language}) {
        return $string;
    }

    my ($translation, $fuzzy, $comment, $need_save) =
        $self->internal_get_translation($string, $context, $namespace, $filepath, $lang, $disallow_similar_lang, $item_id, $key);

    # if need_save flag is set, this means that translation comes from a fuzzy match
    # and it needs to be applied back to the database; note that if disallow_similar_lang
    # flag set (in other words, when getting the translation from a similar language)
    # we do not save the translation (but pass the need_save flag status back to the caller)

    if ($need_save && !$disallow_similar_lang) {
        # Saving the updated translation
        if ($item_id) {
            print "\t\t[$item_id/$lang] $translation\n";
            $self->{db}->set_translation($item_id, $lang, $translation, $fuzzy, $comment);
        } else {
            if (!$self->{job}->{output_only_mode}) {
                if ($self->{debug}) {
                    print "\t\t? [need_save, but item_id not defined]\n";
                    print "::>> string=[$string], context=[$context], namespace=[$namespace], filepath=[$filepath], lang=[$lang], disallow_similar_lang=[$disallow_similar_lang], item_id=[$item_id], key=[$key])\n";
                    print "::<< translation=[$translation], fuzzy=[$fuzzy], comment=[$comment], need_save=[$need_save]\n";
                }
            }
        }
    }

    # return translation

    return ($translation, $translation ne '' ? $fuzzy : undef, $comment, $need_save);
}

sub internal_get_translation { # from database
    my ($self, $string, $context, $namespace, $filepath, $lang, $disallow_similar_lang, $item_id, $key) = @_;

    # try to get translation by calling registered plugin callbacks
    # (phase 1, before even looking for existing translations)
    my ($translation, $fuzzy, $comment, $need_save) = $self->run_callbacks(
            'get_translation_pre',
            $string, $context, $namespace, $filepath, $lang, $disallow_similar_lang, $item_id, $key
        );
    $translation = NFC($translation) if $translation ne '';
    return ($translation, $fuzzy, $comment, $need_save) if ($translation ne '' || $comment ne '');

    # Find exact match for given namespace, file path and context

    ($translation, $fuzzy, $comment, my $merge, my $skip) = $self->{db}->get_translation($item_id, $lang, 1); # allow skip
    return if $skip;
    return ($translation, $fuzzy, $comment, undef) if ($translation ne '' || $comment ne '');

    # check what the best translation is and if there are multiple translations
    # in the database for this exact string

    # try to search for best translation in current language
    if ($self->{job}->{reuse_translations}) {
        # Find the best match from other files or namespaces
        my ($translation, $fuzzy, $comment, $multiple_variants) = $self->{db}->find_best_translation(
            $namespace, $filepath, $string, $context, $lang, $self->{job}->{reuse_orphaned}, $self->{job}->{reuse_uncertain}
        );

        if ($multiple_variants && !$self->{job}->{reuse_uncertain}) {
            print "Multiple translations found, won't reuse any because 'reuse_uncertain' mode is set to NO\n" if $self->{debug};
            # return now, otherwise the translation might be obtained in e.g. transform plugin
            # from a similar string that has just one translation variant
            return;
        }

        if ($fuzzy) {
            # if the fuzzy flag is already set, always leave it as is,
            # even if the language is listed under `reuse_as_not_fuzzy` list
        } else {
            # the fuzzy flag is not set, but we might want to raise it here
            my $lang_as_fuzzy = is_flag_set($self->{job}->{reuse_as_fuzzy}, $lang);
            my $lang_as_not_fuzzy = is_flag_set($self->{job}->{reuse_as_not_fuzzy}, $lang);
            $fuzzy = 1 if $lang_as_fuzzy || ($self->{job}->{reuse_as_fuzzy_default} && !$lang_as_not_fuzzy);
        }
        return ($translation, $fuzzy, $comment, 1) if ($translation ne '' || $comment ne '');
    }

    # try to get translation by calling registered plugin callbacks
    # (phase 2, after looking up the database)
    ($translation, $fuzzy, $comment, $need_save) = $self->run_callbacks(
            'get_translation',
            $string, $context, $namespace, $filepath, $lang, $disallow_similar_lang, $item_id, $key
        );
    $translation = NFC($translation) if $translation ne '';
    return ($translation, $fuzzy, $comment, $need_save) if ($translation ne '' || $comment ne '');

    # Otherwise, try to look for a translation from a similar language

    if ($self->{job}->{reuse_translations} && !$disallow_similar_lang && exists $self->{job}->{similar_languages}) {
        foreach my $rule (@{$self->{job}->{similar_languages}}) {
            if ($rule->{destination} eq $lang) {
                foreach my $source_lang (sort @{$rule->{source}}) {
                    # pass disallow_similar_lang = 1 to avoid infinite recursion
                    my ($translation, $fuzzy, $comment, $need_save) =
                        $self->get_translation($string, $context, $namespace, $filepath, $source_lang, 1, $item_id, $key);
                    # force fuzzy flag if $rule->{as_fuzzy} is true; otherwise, use the original fuzzy flag value
                    $fuzzy = $fuzzy || $rule->{as_fuzzy};
                    return ($translation, $fuzzy, $comment, 1) if ($translation ne '' || $comment ne '');
                }
            }
        }
    }

    # Otherwise, return nothing
}

1;
