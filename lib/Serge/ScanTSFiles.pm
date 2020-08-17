package Serge::ScanTSFiles;
use parent Serge::Engine;

use strict;

use Serge::Util;
use Time::HiRes qw(gettimeofday tv_interval);

sub process_job {
    my ($self, $job) = @_;

    $self->init_job($job);
    $self->adjust_job_defaults($job);
    $self->adjust_destination_languages($job);

    #$self->{job}->{debug} = 1;

    # This hash will contain the list of known translation directories across all jobs
    $self->{ts_directories} = {} unless exists $self->{ts_directories};

    # This hash will contain the list of known translation files across all jobs
    $self->{known_files} = {} unless exists $self->{known_files};

    # for .po scanning purposes, skip jobs having output_only_mode as well

    if ($self->job_can_run($job) && !$job->{output_only_mode}) {
        print "\n\n*** [".$job->{id}."] ".$job->{name}." ***\n";
    } else {
        print "*** SKIPPING: [".$job->{id}."] ".$job->{name}." ***\n";
        return;
    }

    my $ts_file_path = $job->{ts_file_path};
    die "ERROR: ts_file_path not defined" unless $ts_file_path;
    my ($ts_base_dir, $extra) = split(/[\\\/]%(CULTURE|LANG[^%]*|LOCALE[^%]*)%[\\\/]/, $ts_file_path);
    # die here, otherwise there's a chance some translation interchange files will be deleted by mistake
    die "ERROR: ts_file_path has no %CULTURE%, %LANG% or %LOCALE% macro provided" unless $extra ne '';
    $ts_base_dir =~ s/\\/\//sg; # always use forward slash for consistency

    die "source_dir [$job->{source_dir}] doesn't exist. Try doing an initial data checkout (`serge pull --initialize`), or reconfigure your job" unless -d $job->{source_dir};

    $self->{ts_directories}->{$ts_base_dir} = 1;

    # always go through all destination languages with no optimizations
    $self->{job}->{modified_languages} = $self->{job}->{destination_languages};

    print "TS base dir: [".$ts_base_dir."]\n";

    # this will just scan the files and prepare the list of relative file names
    # in $self->{files} for update_database_from_ts_files() to work properly
    $self->update_database_from_source_files;

    # this will generate the list of target translation files
    # with 'can_process_ts_file' callback processing
    $self->update_database_from_ts_files;
}

sub update_database_from_source_files {
    my ($self) = @_;

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

    # now parse files; during this process, plugins may report that some files
    # should be considered orphaned

    foreach my $file_rel (@{$self->{found_files}}) {
        $self->parse_source_file($file_rel);
    }
}

sub parse_source_file {
    my ($self, $file_rel) = @_;

    # set global CURRENT_FILE_REL variable to current relative file path
    # as it will later be used in different parts
    $self->{current_file_rel} = $file_rel;

    # the file source is only needed when 'after_load_source_file_for_processing' or
    # 'can_process_source_file' callback want to filter out files by their content

    # TODO: to optimize processing, the host could query the plugins if they need
    # the file content, and load the file only when necessary

    my ($src) = $self->read_file($self->get_full_source_path($self->{current_file_rel}));

    $self->run_callbacks('after_load_source_file_for_processing', $self->{current_file_rel}, \$src);

    my $result = combine_and($self->run_callbacks('is_file_orphaned', $self->{current_file_rel}));
    if ($result eq '1') {
        print "\tSkip $self->{current_file_rel} because callback said it is orphaned\n" if $self->{debug};

        # remove the file from $self->{file_mappings} hash
        delete $self->{file_mappings}->{$self->{current_file_rel}};

        return;
    }

    $result = combine_and(1, $self->run_callbacks('can_process_source_file', $self->{current_file_rel}, undef, \$src));
    if ($result eq '0') {
        print "\tSkip $self->{current_file_rel} because at least one callback returned 0\n" if $self->{debug};
        return;
    }

    $self->{files}->{$self->{current_file_rel}} = [1]; # a dummy array of a positive size (originally this should include a list of item_id)
}

sub update_database_from_ts_files_lang {
    my ($self, $lang) = @_;

    return if ($lang eq $self->{job}->{source_language});

    foreach my $file (sort keys %{$self->{files}}) {
        $self->update_database_from_ts_files_lang_file($lang, $file);
    }
}

sub update_database_from_ts_files_lang_file {
    my ($self, $lang, $relfile) = @_;

    my $fullpath = $self->get_full_ts_file_path($relfile, $lang);

    print "\t$fullpath\n";

    if (!-f $fullpath) {
        print "\tFile does not exist: $fullpath\n" if $self->{debug};
        return;
    }

    my $result = combine_and(1, $self->run_callbacks('can_process_ts_file', $relfile, $lang));
    if ($result eq '0') {
        print "\tSkip $fullpath because at least one callback returned 0\n" if $self->{debug};
        return;
    }

    $self->{known_files}->{$fullpath} = 1;
}

1;
