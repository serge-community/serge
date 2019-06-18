package Serge::DB::Cached;
use parent Serge::DB;

use strict;

no warnings qw(uninitialized);

use Digest::MD5 qw(md5);
use Encode qw(encode_utf8);
use Serge::Util qw(generate_key generate_hash);
use Time::HiRes qw(gettimeofday tv_interval);

our $DEBUG = $ENV{CI} ne ''; # use debug mode from under CI environment to ensure better coverage

our $CACHING_STRATEGY = lc($ENV{SERGE_DB_CACHING_STRATEGY}) || "db";
if ($CACHING_STRATEGY !~ m/^(db|namespace|file|string)$/) {
    die "Invalid SERGE_DB_CACHING_STRATEGY value: [$ENV{SERGE_DB_CACHING_STRATEGY}]. ".
        "Valid values are: 'db' (default), 'namespace', 'file' and 'string'.\n";
}

sub open {
    my ($self, $source, $username, $password) = @_;

    # if parameters din't change, just stay connected
    # to the previously opened database

    if (exists $self->{dsn} and
        ($self->{dsn}->{source} eq $source) and
        ($self->{dsn}->{username} eq $username) and
        ($self->{dsn}->{password} eq $password)) {
        print "Reusing previously opened database connection\n";
        return $self->{dbh};
    }

    $self->close if $self->{dbh};

    $self->{dsn} = {
        source => $source,
        username => $username,
        password => $password
    };

    $self->{dsn_hash} = generate_hash($source, $username, $password);

    $self->{cache} = {
        job => {},
        properties => {},
        translations => {}
    };

    return $self->SUPER::open($source, $username, $password);
}

sub close {
    my ($self) = @_;
    $self->{cache} = {};
    delete $self->{dsn};
    delete $self->{dsn_hash};
    return $self->SUPER::close;
}

sub _copy_props {
    my ($self, $h_old, $h_new) = @_;

    my $result = undef;
    foreach (keys %$h_new) {
        $result = 1 if $h_new->{$_} ne $h_old->{$_};
        $h_old->{$_} = $h_new->{$_};
    }
    return $result;
}

#
#  strings
#

sub get_string_id {
    my ($self, $string, $context, $nocreate) = @_;

    my $key = 'string_id:'.generate_key($string, $context);

    if (exists $self->{cache}->{job}->{$key}) {
        my $id = $self->{cache}->{job}->{$key};
        return $id if $id or $nocreate;
    }

    return $self->{cache}->{job}->{$key} = $self->SUPER::get_string_id($string, $context, $nocreate);
}

sub update_string_props {
    my ($self, $string_id, $props) = @_;

    my $key = "string:$string_id";

    my $h = $self->{cache}->{job}->{$key};
    $h = $self->{cache}->{job}->{$key} = $self->SUPER::get_string_props($string_id) unless $h;

    return $self->SUPER::update_string_props($string_id, $props) if $self->_copy_props($h, $props);
}

sub get_string_props {
    my ($self, $string_id) = @_;

    my $key = "string:$string_id";

    return $self->{cache}->{job}->{$key} if exists $self->{cache}->{job}->{$key};

    return $self->{cache}->{job}->{$key} = $self->SUPER::get_string_props($string_id);
}

#
#  items
#

sub get_item_id {
    my ($self, $file_id, $string_id, $hint, $nocreate) = @_;

    my $key = "item_id:$file_id:$string_id";

    if (exists $self->{cache}->{job}->{$key}) {
        my $id = $self->{cache}->{job}->{$key};
        return $id if $id or $nocreate;
    }

    # now check if the file was preloaded in the cache,
    # and if it was (which means that all known item_id should
    # also be there in the cache, then return undef if $nocreate flag is set

    my $file_key = "file:$file_id";

    if (exists $self->{cache}->{job}->{$file_key}) {
        return undef if $nocreate;
    }

    $hint = undef if $hint eq '';

    return $self->{cache}->{job}->{$key} = $self->SUPER::get_item_id($file_id, $string_id, $hint, $nocreate);
}

sub update_item_props {
    my ($self, $item_id, $props) = @_;

    my $key = "item:$item_id";

    my $h = $self->{cache}->{job}->{$key};
    $h = $self->{cache}->{job}->{$key} = $self->SUPER::get_item_props($item_id) unless $h;

    return $self->SUPER::update_item_props($item_id, $props) if $self->_copy_props($h, $props);
}

sub get_item_props {
    my ($self, $item_id) = @_;

    my $key = "item:$item_id";

    return $self->{cache}->{job}->{$key} if exists $self->{cache}->{job}->{$key};

    return $self->{cache}->{job}->{$key} = $self->SUPER::get_item_props($item_id);
}

#
#  files
#

sub get_file_id {
    my ($self, $namespace, $job, $path, $nocreate) = @_;

    my $key = 'file_id:'.md5(encode_utf8(join("\001", ($namespace, $job, $path))));

    if (exists $self->{cache}->{job}->{$key}) {
        my $id = $self->{cache}->{job}->{$key};
        return $id if $id or $nocreate;
    }

    return $self->{cache}->{job}->{$key} = $self->SUPER::get_file_id($namespace, $job, $path, $nocreate);
}

sub update_file_props {
    my ($self, $file_id, $props) = @_;

    my $key = "file:$file_id";

    my $h = $self->{cache}->{job}->{$key};
    $h = $self->{cache}->{job}->{$key} = $self->SUPER::get_file_props($file_id) unless $h;

    return $self->SUPER::update_file_props($file_id, $props) if $self->_copy_props($h, $props);
}

sub get_file_props {
    my ($self, $file_id) = @_;

    my $key = "file:$file_id";

    return $self->{cache}->{job}->{$key} if exists $self->{cache}->{job}->{$key};

    return $self->{cache}->{job}->{$key} = $self->SUPER::get_file_props($file_id);
}

#
#  translations
#

sub get_translation_id {
    my ($self, $item_id, $lang, $string, $fuzzy, $comment, $merge, $nocreate) = @_;

    my $key = "translation_id:$item_id:$lang";

    if (exists $self->{cache}->{job}->{$key}) {
        my $id = $self->{cache}->{job}->{$key};
        return $id if $id or $nocreate;
    }

    return $self->{cache}->{job}->{$key} = $self->SUPER::get_translation_id($item_id, $lang, $string, $fuzzy, $comment, $merge, $nocreate);
}

sub update_translation_props {
    my ($self, $translation_id, $props) = @_;

    my $key = "translation:$translation_id";

    my $h = $self->{cache}->{job}->{$key};
    $h = $self->{cache}->{job}->{$key} = $self->SUPER::get_translation_props($translation_id) unless $h;

    return $self->SUPER::update_translation_props($translation_id, $props) if $self->_copy_props($h, $props);
}

sub get_translation_props {
    my ($self, $translation_id) = @_;

    my $key = "translation:$translation_id";

    return $self->{cache}->{job}->{$key} if exists $self->{cache}->{job}->{$key};

    return $self->{cache}->{job}->{$key} = $self->SUPER::get_translation_props($translation_id);
}

sub set_translation {
    my ($self, $item_id, $lang, $string, $fuzzy, $comment, $merge) = @_;

    $string = undef if $string eq '';
    $comment = undef if $comment eq '';
    $fuzzy = $fuzzy ? 1 : 0;
    $merge = $merge ? 1 : 0;

    my $id = $self->get_translation_id($item_id, $lang, $string, $fuzzy, $comment, $merge); # create if necessary

    # if translations cache was preloaded, update it as well
    my $cache = $self->{cache}->{translations}->{$lang};
    if ($cache) {
        my $i = $self->get_item_props($item_id);
        if ($i) {
            my $s = $self->get_string_props($i->{string_id});
            my $f = $self->get_file_props($i->{file_id});
            my $skey = generate_key($s->{string});

            $cache->{$skey} = {} unless exists $cache->{$skey};
            $cache->{$skey}->{$item_id} = {
                namespace => $f->{namespace},
                path => $f->{path},
                context => $s->{context},
                orphaned => undef,
                string => $string,
                fuzzy => $fuzzy,
                comment => $comment,
            };
        }
    }

    $self->update_translation_props($id, {
        string => $string,
        fuzzy => $fuzzy,
        comment => $comment,
        merge => $merge,
    });
}

#
#  properties
#

sub get_property_id {
    my ($self, $property, $value, $nocreate) = @_;

    my $key = "property_id:$property";

    if (exists $self->{cache}->{properties}->{$key}) {
        my $id = $self->{cache}->{properties}->{$key};
        return $id if $id or $nocreate;
    }

    return $self->{cache}->{$key} = $self->SUPER::get_property_id($property, $value, $nocreate);
}

sub update_property_props {
    my ($self, $property_id, $props) = @_;

    my $key = "property:$property_id";

    my $h = $self->{cache}->{properties}->{$key};
    $h = $self->{cache}->{properties}->{$key} = $self->SUPER::get_property_props($property_id) unless $h;

    return $self->SUPER::update_property_props($property_id, $props) if $self->_copy_props($h, $props);
}

sub get_property_props {
    my ($self, $property_id) = @_;

    my $key = "property:$property_id";

    return $self->{cache}->{properties}->{$key} if exists $self->{cache}->{properties}->{$key};
    return $self->{cache}->{properties}->{$key} = $self->SUPER::get_property_props($property_id);
}

sub get_property {
    my ($self, $property) = @_;

    my $id = $self->get_property_id($property, undef, 1); # do not create

    if ($id) {
        my $props = $self->get_property_props($id);
        return $props->{value} if $props;
    }
    return $self->SUPER::get_property($property);
}

sub set_property {
    my ($self, $property, $value) = @_;

    my $id = $self->get_property_id($property, $value); # create if necessary

    return $self->update_property_props($id, {'value' => $value});
}

#
# Other
#

sub get_all_items_for_file {
    my ($self, $file_id) = @_;

    my $key = "all_items:$file_id";

    return $self->{cache}->{job}->{$key} if exists $self->{cache}->{job}->{$key};
    return $self->{cache}->{job}->{$key} = $self->SUPER::get_all_items_for_file($file_id);
}

sub get_file_completeness_ratio {
    my ($self, $file_id, $lang, $total) = @_;

    my $key = "completeness:$file_id:$lang:$total";

    return $self->{cache}->{job}->{$key} if exists $self->{cache}->{job}->{$key};
    return $self->{cache}->{job}->{$key} = $self->SUPER::get_file_completeness_ratio($file_id, $lang, $total);
}

sub get_all_files_for_job {
    my ($self, $namespace, $job) = @_;

    my $key = "all_files:$namespace:$job";

    return $self->{cache}->{job}->{$key} if exists $self->{cache}->{job}->{$key};
    return $self->{cache}->{job}->{$key} = $self->SUPER::get_all_files_for_job($namespace, $job);
}

sub get_translation {
    my ($self, $item_id, $lang, $allow_skip) = @_;

    my $translation_id = $self->get_translation_id($item_id, $lang, undef, undef, undef, undef, 1); # do not create

    if ($translation_id) {
        my $i = $self->get_item_props($item_id);
        my $s = $self->get_string_props($i->{string_id});

        my $props = $self->get_translation_props($translation_id);
        return if $s->{skip} and !$allow_skip;
        return ($props->{string}, $props->{fuzzy}, $props->{comment}, $props->{merge}, $s->{skip});
    }
}

sub preload_full_cache_items {
    my ($self, $lang_cache, $lang, $extra_params) = @_;


    my $extra_query;
    if ($CACHING_STRATEGY eq 'db') {
        $extra_query = '';
    } elsif ($CACHING_STRATEGY eq 'namespace') {
        $extra_query = <<__END__;
		AND s.id IN (
			SELECT DISTINCT s.id

        	FROM strings s

        	JOIN items i ON i.string_id = s.id
        	JOIN files f ON i.file_id = f.id

			WHERE s.skip = 0
			AND f.namespace = ?
		)
__END__
    } elsif ($CACHING_STRATEGY eq 'file') {
        $extra_query = <<__END__;
		AND s.id IN (
			SELECT DISTINCT s.id

        	FROM strings s

        	JOIN items i ON i.string_id = s.id
        	JOIN files f ON i.file_id = f.id

			WHERE s.skip = 0
			AND f.namespace = ?
            AND f.path = ?
		)
__END__
    } elsif ($CACHING_STRATEGY eq 'string') {
        $extra_query = <<__END__;
		AND s.skip = 0
        AND s.string = ?
__END__
    }

    my $sqlquery = <<__END__;
        SELECT s.id AS string_id, s.string, s.context, i.id as item_id, i.orphaned,
        f.path, f.namespace, f.orphaned as f_orphaned,
        t.language, t.string AS translation, t.fuzzy, t.comment

        FROM translations t

        JOIN items i ON t.item_id = i.id
        JOIN strings s ON i.string_id = s.id
        JOIN files f ON i.file_id = f.id

        WHERE t.language = ?
        $extra_query
__END__

    my $sth = $self->prepare($sqlquery);
    my $n = 1;
    $sth->bind_param($n++, $lang) || die $sth->errstr;
    map { $sth->bind_param($n++, $_) || die $sth->errstr } @$extra_params;
    $sth->execute || die $sth->errstr;

    while (my $hr = $sth->fetchrow_hashref()) {
        my $item_id = $hr->{item_id};
        my $skey = generate_key($hr->{string});

        $lang_cache->{$skey} = {} unless exists $lang_cache->{$skey};
        $lang_cache->{$skey}->{$item_id} = {
            namespace => $hr->{namespace},
            path => $hr->{path},
            context => $hr->{context},
            orphaned => $hr->{orphaned} || $hr->{f_orphaned},
            string => $hr->{translation},
            fuzzy => $hr->{fuzzy},
            comment => $hr->{comment},
        };
    }

    $sth->finish;
    $sth = undef;
}

sub preload_translation_cache_for_lang {
    my ($self, $lang, $namespace, $filepath, $string) = @_;

    my $lang_cache = $self->{cache}->{translations}->{$lang};
    if (!$lang_cache) {
        $lang_cache = $self->{cache}->{translations}->{$lang} = {};
    }

    my $key;
    if ($CACHING_STRATEGY eq 'db') {
        $key = generate_hash('db', $self->{dsn_hash});
    } elsif ($CACHING_STRATEGY eq 'namespace') {
        $key = generate_hash('namespace', $namespace);
    } elsif ($CACHING_STRATEGY eq 'file') {
        $key = generate_hash('file', $namespace, $filepath);
    } elsif ($CACHING_STRATEGY eq 'string') {
        $key = generate_hash('string', $string);
    }

    if ($lang_cache->{key} ne $key) {
        $lang_cache = $self->{cache}->{translations}->{$lang} = {};
        $lang_cache->{key} = $key;

        # loading the cache

        print "Loading the cache ($lang, $CACHING_STRATEGY)\n" if $DEBUG;

        my $extra_params;
        if ($CACHING_STRATEGY eq 'db') {
            $extra_params = [];
        } elsif ($CACHING_STRATEGY eq 'namespace') {
            $extra_params = [$namespace];
        } elsif ($CACHING_STRATEGY eq 'file') {
            $extra_params = [$namespace, $filepath];
        } elsif ($CACHING_STRATEGY eq 'string') {
            $extra_params = [$string];
        }

        my $start = [gettimeofday];

        $self->preload_full_cache_items($lang_cache, $lang, $extra_params);

        my $delta = tv_interval($start);
        $self->{preload_translation_candidates_total_time} += $delta;
        print "preload_translation_cache_for_lang($lang, $CACHING_STRATEGY) took $delta seconds ($self->{preload_translation_candidates_total_time} total seconds)\n";
    }
}

#
# This preloads all cache data structures for the given job
#
sub preload_cache_for_job {
    my ($self, $namespace, $job, $langs) = @_;

    $self->{cache}->{job} = {}; # clear the previously populated cache

    print "Preloading cache for job '$job' in namespace '$namespace'...\n";

    my $languages_sql = $langs ? "AND (translations.language IS NULL OR translations.language IN ('".join("','", @$langs)."')) " : "";

    my $sqlquery =
        "SELECT ".
        "files.id as file_id, files.namespace, files.job, files.path, ".
        "files.orphaned as file_orphaned, ".

        "items.id AS item_id, items.orphaned as item_orphaned, ".
        "items.hint as item_hint, items.comment AS item_comment, ".

        "strings.id as string_id, strings.string, strings.context, strings.skip, ".

        "translations.id as translation_id, translations.language, ".
        "translations.string as translation, translations.fuzzy, ".
        "translations.comment, translations.merge ".

        "FROM files ".

        "LEFT OUTER JOIN items ".
        "ON items.file_id = files.id ".

        "LEFT OUTER JOIN strings ".
        "ON strings.id = items.string_id ".

        "LEFT OUTER JOIN translations ".
        "ON translations.item_id = items.id ".
        $languages_sql.

        "WHERE files.namespace = ? ".
        "AND files.job = ?";

    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $namespace) || die $sth->errstr;
    $sth->bind_param(2, $job) || die $sth->errstr;
    $sth->execute || die $sth->errstr;

    my $job_cache = $self->{cache}->{job};

    while (my $hr = $sth->fetchrow_hashref()) {

        # cache 'item:<ITEM_ID>'

        my $key = 'item:'.$hr->{item_id};

        $job_cache->{$key} = {
            file_id => $hr->{file_id},
            string_id => $hr->{string_id},
            hint => $hr->{item_hint},
            comment => $hr->{item_comment},
            orphaned => $hr->{item_orphaned}
        };

        if ($hr->{translation_id}) {

            # cache 'translation_id:<ITEM_ID>:<LANG>'

            $key = 'translation_id:'.$hr->{item_id}.':'.$hr->{language};
            $job_cache->{$key} = $hr->{translation_id};

            # cache 'translation:<TRANSLATION_ID>'

            $key = 'translation:'.$hr->{translation_id};

            $job_cache->{$key} = {
                string => $hr->{translation},
                fuzzy => $hr->{fuzzy},
                comment => $hr->{comment},
                merge => $hr->{merge},
                skip => $hr->{skip} # copy strings.skip flag here for easier lookup
            };
        }

        # cache 'file:<FILE_ID>'

        $key = 'file:'.$hr->{file_id};
        $job_cache->{$key} = {
            job => $hr->{job},
            namespace => $hr->{namespace},
            path => $hr->{path},
            orphaned => $hr->{file_orphaned}
        };

        # cache 'all_files:<NAMESPACE>:<JOB>'

        $key = 'all_files:'.$hr->{namespace}.':'.$hr->{job};
        my $h = (exists $job_cache->{$key}) ? $job_cache->{$key} : ($job_cache->{$key} = {});
        if (!exists $h->{$hr->{path}}) {
            $h->{$hr->{path}} = {
                id => $hr->{file_id},
                orphaned => $hr->{file_orphaned}
            };
        }

        # cache 'all_items:<FILE_ID>'

        if ($hr->{item_id}) {
            $key = 'all_items:'.$hr->{file_id};
            my $h = (exists $job_cache->{$key}) ? $job_cache->{$key} : ($job_cache->{$key} = {});
            $h->{$hr->{item_id}} = $hr->{item_orphaned};
        }

        # cache 'file_id:<HASH>'

        $key = 'file_id:'.md5(encode_utf8(join("\001", ($namespace, $job, $hr->{path}))));
        $job_cache->{$key} = $hr->{file_id};

        # cache 'string_id:<HASH>'

        $key = 'string_id:'.generate_key($hr->{string}, $hr->{context});
        $job_cache->{$key} = $hr->{string_id};

        # cache 'string:<STRING_ID>'

        $key = 'string:'.$hr->{string_id};
        $job_cache->{$key} = {
            string => $hr->{string},
            context => $hr->{context},
            skip => $hr->{skip}
        };

        # cache 'item_id:<FILE_ID>:<STRING_ID>'

        $key = 'item_id:'.$hr->{file_id}.':'.$hr->{string_id};
        $job_cache->{$key} = $hr->{item_id};
    }

    $sth->finish;
    $sth = undef;
}

sub preload_properties {
    my ($self) = @_;

    return if $self->{cache}->{properties};

    my $props_cache = $self->{cache}->{properties} = {};

    print "Preloading properties...\n";

    my $sqlquery =
        "SELECT * ".
        "FROM properties";

    my $sth = $self->prepare($sqlquery);
    $sth->execute || die $sth->errstr;

    while (my $hr = $sth->fetchrow_hashref()) {

        # cache 'property_id:<PROPERTY>'

        my $key = 'property_id:'.$hr->{property};
        $props_cache->{$key} = $hr->{id};

        # cache 'property:<PROPERTY_ID>'

        $key = 'property:'.$hr->{id};

        $props_cache->{$key} = {
            value => $hr->{value},
        };
    }

    $sth->finish;
    $sth = undef;
}

sub find_best_translation {
    my $self = shift;
    my ($namespace, $filepath, $string, $context, $lang,
        $allow_orphaned, $allow_fuzzy, $allow_multiple_variants) = @_;

    # Now that we hit the item we have no translation for, and need to query
    # the database for the best translation, preload the portion of the cache
    # for the target language based on the current caching strategy.
    $self->preload_translation_cache_for_lang($lang, $namespace, $filepath, $string);

    my $cache = $self->{cache}->{translations}->{$lang};
    my $skey = generate_key($string);

    return unless $cache->{$skey};

    my $best_fitness = -1;
    my @translations;
    my $fuzzy;
    my $comment;
    my $variants = {};
    foreach my $hr (values %{$cache->{$skey}}) {
        next if $hr->{orphaned} && !$allow_orphaned;
        next if $hr->{fuzzy} && !$allow_fuzzy;
        $variants->{$hr->{string}}++;

        my $fitness = 0;
        $fitness++ if $hr->{namespace} eq $namespace;
        $fitness++ if $hr->{path} eq $filepath;
        $fitness++ if $hr->{context} eq $context;
        $fitness++ if !$hr->{orphaned};
        if ($fitness > $best_fitness) {
            $best_fitness = $fitness;
            @translations = ($hr->{string});
            $fuzzy = $hr->{fuzzy};
            $comment = $hr->{comment};
        } elsif ($fitness == $best_fitness) {
            push @translations, $hr->{string};
        }
    }

    my $multiple_variants = keys %$variants > 1;
    if ($multiple_variants && !$allow_multiple_variants) {
        # return an empty translation along with the $multiple_variants flag
        # so that the parent code can understand the reason
        return (undef, undef, undef, $multiple_variants);
    }

    # for multiple translations of the same fitness,
    # return the first one in alphabetical sort order
    # to make sure the same translation is picked
    # every time, and not a random one

    return ((sort @translations)[0], $fuzzy, $comment, $multiple_variants);
}

# helper function used in tools/import_from_ttx.pl
sub get_source_string {
    my ($self, $item_id) = @_;

    $self->_check_item_id($item_id) if $DEBUG;

    # lookup for the source string for the given item

    my $sqlquery =
        "SELECT ".
        "strings.string, strings.context, strings.skip ".
        "FROM items ".
        "LEFT OUTER JOIN strings ON items.string_id = strings.id ".
        "WHERE items.id = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $item_id) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;

    return unless $hr;

    return ($hr->{string}, $hr->{context}, $hr->{skip});
}

1;
