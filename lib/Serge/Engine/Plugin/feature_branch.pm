package Serge::Engine::Plugin::feature_branch;
use parent Serge::Plugin::Base::Callback;

use strict;

no warnings qw(uninitialized);

use Serge::Util qw(generate_key set_flags);
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
        after_job => \&after_job,
        can_extract => \&can_extract,
        get_translation_pre => \&get_translation_pre,
    });

    $self->{cache} = {};
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
    set_flags($phases, 'before_job', 'after_job', 'can_extract', 'get_translation_pre');

    die "This plugin attaches itself to specific phases; please don't specify phases in the configuration file" unless @$phases == 4;
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
        $self->{cache} = $engine->{plugin_data}->{feature_branch}->{$master_job_id} = {};
        $self->{cache}->{''} = {};

    } else {
        print "Running feature_branch plugin in slave mode\n";

        if (!exists $engine->{plugin_data} ||
            !exists $engine->{plugin_data}->{feature_branch} ||
            !exists $engine->{plugin_data}->{feature_branch}->{$master_job_id}) {
            die "Can't run job with feature_branch plugin in slave mode before (or without) the master job\n";
        }

        $self->{cache} = $engine->{plugin_data}->{feature_branch}->{$master_job_id};
    }
}

sub after_job {
   my ($self, $phase) = @_;

    return unless $self->{master_mode}; # do nothing in slave mode

    # cache translations for slave jobs
    $self->load_translations;
}

sub load_translations {
    my ($self) = @_;

    my $start = [gettimeofday];

    my $job_id = $self->{parent}->{id}; # we're the master job
    my $engine = $self->{parent}->{engine};
    my $db = $engine->{db};
    my $cache = $self->{cache};


    my @languages = @{$self->{parent}->{destination_languages}};
    my $sql_lang_filter = '';
    if (@languages > 0) {
        my $placeholders = join(', ', ('?') x @languages);
        $sql_lang_filter = "AND (t.language is NULL OR t.language IN ($placeholders))";
    }
    print "feature_branch plugin: caching strings and known translations...\n";

    # in our query we want to include orphaned translations because some items
    # or files that are already orphaned on the master branch can still be there
    # in the slave (feature) branch, and we want to reuse them;
    # we will also select non-translated items here at once (though there will be
    # many string+context duplicates, but calculating keys for these extra pairs
    # shouldn't be much of a problem)
    my $sqlquery = <<__END__;
        SELECT s.string, s.context, t.language, t.string as translation
        FROM items i

        JOIN strings s
        ON i.string_id = s.id

        JOIN files f
        ON i.file_id = f.id

        LEFT OUTER JOIN translations t
        ON t.item_id = i.id

        WHERE s.skip = 0
        AND f.namespace = ?
        AND f.job = ?
        $sql_lang_filter
__END__

    my $sth = $db->prepare($sqlquery);

    my $n = 1;
    $sth->bind_param($n++, $self->{parent}->{db_namespace}) || die $sth->errstr;
    $sth->bind_param($n++, $job_id) || die $sth->errstr;
    map {
        $sth->bind_param($n++, $_) || die $sth->errstr;
    } @languages;
    $sth->execute || die $sth->errstr;

    my $n = 0;
    while (my $hr = $sth->fetchrow_hashref()) {
        $n++;
        my $lang = $hr->{language};
        my $skey = generate_key($hr->{string}, $hr->{context});
        # save string+context key (to know the string exists in master job
        # even if it doesn't have a translation)
        $cache->{''} = {} unless defined $cache->{''};
        $cache->{''}->{$skey} = 1;
        # save translation
        if ($lang ne '') {
            $cache->{$lang} = {} unless defined $cache->{$lang};
            $cache->{$lang}->{$skey} = $hr->{translation};
        }
    }
    $sth->finish;
    $sth = undef;

    my $delta = tv_interval($start);
    print "feature_branch::load_translations() took $delta seconds\n";
}

sub get_translation_pre {
    my ($self, $phase, $string, $context, $namespace, $filepath, $lang, $disallow_similar_lang, $item_id, $key) = @_;

    return () if $self->{master_mode}; # do nothing in master mode

    # otherwise, return current translation (or empty array if there's no matching translation)
    my $key = generate_key($string, $context);
    return exists $self->{cache}->{$lang}->{$key} ? ($self->{cache}->{$lang}->{$key}, undef, undef, undef) : ();
}

sub string_exists {
    my ($self, $stringref, $context) = @_;

    return exists $self->{cache}->{''}->{generate_key($$stringref, $context)};
}

sub can_extract {
    my ($self, $phase, $file, $lang, $stringref, $hintref, $context, $key) = @_;

    # extract everything for master job, and collect string+context pairs
    if ($self->{master_mode}) {
        $self->{cache}->{''}->{generate_key($$stringref, $context)} = 1;
        return 1;
    }

    # otherwise, we're in a slave job

    # if we're generating localized files, $lang will be set
    return 1 if defined $lang; # extract everything to translate all the strings, not just overlay ones

    # otherwise (when $lang is not set) we're parsing the source file
    return $self->string_exists($stringref, $context, ) ? 0 : 1; # extract only strings which are missing from the master job
}

1;