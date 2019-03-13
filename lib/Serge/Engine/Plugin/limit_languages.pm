package Serge::Engine::Plugin::limit_languages;
use parent Serge::Plugin::Base::Callback;

use strict;

use Config::Neat::Inheritable;
use Config::Neat::Array;
use Data::Dumper;

our %limitLanguages;
our %orphaned;

sub name {
    return 'Limit destination languages on a per-file basis';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        debug                                  => 'BOOLEAN',

        if => {''                              => 'LIST',

            '*' => {
                file_matches                   => 'ARRAY',
                file_doesnt_match              => 'ARRAY',

                content_matches                => 'ARRAY',
                content_doesnt_match           => 'ARRAY',

                then => {
                    split_by                   => 'STRING',

                    limit_languages            => 'ARRAY',
                    include_languages          => 'ARRAY',
                    exclude_languages          => 'ARRAY',

                    limit_to_matched_languages => 'BOOLEAN',
                    include_matched_languages  => 'BOOLEAN',
                    exclude_matched_languages  => 'BOOLEAN',

                    exclude_all_languages      => 'BOOLEAN',
                    include_all_languages      => 'BOOLEAN',
                }

            },
        },
    });

    $self->add({
        after_load_source_file_for_processing => \&after_load_source_file_for_processing,
        is_file_orphaned => \&is_file_orphaned,
        can_process_source_file => \&can_process_source_file,
        can_process_ts_file => \&can_process_file_lang,
        can_generate_ts_file => \&can_process_file_lang,
        can_generate_localized_file => \&can_process_file_lang
    });

    my $c = Config::Neat::Inheritable->new();
    my $data = <<__END__;

    if
    {
        # generic rule to limit translation only to a certain set of languages
        # example: L10N_LIMIT_DESTINATION_LANGUAGES=es-latam,zh-tw
        content_matches    \\bL10N_LIMIT_DESTINATION_LANGUAGES=([\\w,-]*\\w+)?

        then
        {
            split_by           ,
            limit_to_matched_languages
        }
    }

    if
    {
        # generic rule to exclude a certain set of languages
        # example: L10N_EXCLUDE_DESTINATION_LANGUAGES=ar
        content_matches    \\bL10N_EXCLUDE_DESTINATION_LANGUAGES=([\\w,-]*\\w+)?

        then
        {
            split_by           ,
            exclude_matched_languages
        }
    }

__END__
    $data = $c->parse($data, __FILE__);
    $self->{schema}->validate($data);
    $self->{default_if_rules} = $data;
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    # merge rules from the default config
    # (default rules should go before the custom ones
    # so that they can be overridden)

    if (!exists $self->{data}->{if}) {
        $self->{data}->{if} = Config::Neat::Array->new();
    }

    map {
        unshift @{$self->{data}->{if}}, $_;
    } reverse @{$self->{default_if_rules}->{if}};

    # check each rule

    foreach my $block (@{$self->{data}->{if}}) {
        die "'then' block is missing" unless exists $block->{then};
        my $then = $block->{then};

        if (!exists $then->{limit_languages} &&
            !exists $then->{include_languages} &&
            !exists $then->{exclude_languages} &&

            !$then->{limit_to_matched_languages} &&
            !$then->{include_matched_languages} &&
            !$then->{exclude_matched_languages} &&

            !$then->{exclude_all_languages} &&
            !$then->{include_all_languages}) {
            print Dumper($block);
            die "the 'then' block does not have any instructions which languages to limit/include/exclude";
        }

        # check for settings that don't make much sense and are rather confusing

        if (exists $then->{limit_languages} && (exists $then->{include_languages} || exists $then->{include_all_languages})) {
            print Dumper($block);
            die "can't use `limit_languages` together with `include_languages` or `include_all_languages`";
        }

        if (exists $then->{limit_languages} && (exists $then->{exclude_languages} || exists $then->{exclude_all_languages})) {
            print Dumper($block);
            die "can't use `limit_languages` together with `exclude_languages` or `exclude_all_languages`";
        }

        if (exists $then->{include_all_languages} && exists $then->{exclude_all_languages}) {
            print Dumper($block);
            die "can't use `include_all_languages` together with `exclude_all_languages`";
        }

        if (exists $then->{include_all_languages} && (exists $then->{limit_languages} || exists $then->{include_languages})) {
            print Dumper($block);
            die "can't use `include_all_languages` together with `limit_languages` or `include_languages`";
        }

        if (exists $then->{exclude_all_languages} && (exists $then->{limit_languages} || exists $then->{exclude_languages})) {
            print Dumper($block);
            die "can't use `exclude_all_languages` together with `limit_languages` or `exclude_languages`";
        }

        if ((
                $then->{limit_to_matched_languages} ||
                $then->{include_matched_languages} ||
                $then->{exclude_matched_languages}
            ) && !(
                exists $block->{file_matches} ||
                exists $block->{content_matches}
            )) {
            die "`limit_to_matched_languages`, `include_matched_languages` and `exclude_matched_languages` should be used together with either `file_matches` or `content_matches` (or both)";
        }
    }
}

sub adjust_phases {
    my ($self, $phases) = @_;

    $self->SUPER::adjust_phases($phases);

    # this plugin needs to be applied to all its 6 phases (see $self->add({...}) call above)
    die "This plugin needs to be attached to all its supported phases" unless @$phases == 6;
}

# this just checks if all rules are met and the block be actually used
# to modify the list of destination languages
sub check_block {
    my ($self, $block, $file, $strref) = @_;
    my $snippet = (defined $strref && length($$strref) > 200) ? substr($$strref, 0, 197).'...' : $$strref;
    print "[limit_languages]::check_block('$file', ".
          (defined $strref ? "'$snippet', " : '-- no content --, ').
          ")\n" if $self->{parent}->{debug};

    sub _check_rule {
        my ($ruleset, $positive, $value) = @_;

        # if ruleset is not defined, skip the rule by always returning
        # a true value (regardless of what $positive is set to)
        return 1 unless defined $ruleset;

        foreach my $rule (@$ruleset) {
            if ($value =~ m/$rule/s) {
                return $positive;
            }
        }
        return !$positive;
    }

    return 0 unless _check_rule($block->{file_matches},         1,     $file);
    return 0 unless _check_rule($block->{file_doesnt_match},    undef, $file);

    return 0 unless _check_rule($block->{content_matches},      1,     $$strref);
    return 0 unless _check_rule($block->{content_doesnt_match}, undef, $$strref);

    return 1;
}

sub _gather_from_rule {
    my ($self, $ruleset, $split_by, $sref, $out) = @_;

    return unless defined $ruleset;

    foreach my $rule (@$ruleset) {
        print "[rule] $rule\n" if $self->{data}->{debug};
        while ($$sref =~ m/$rule/sg) {
            my $match = $1;
            print "[match] $match\n" if $self->{data}->{debug};
            if (defined $match) {
                if (defined $split_by) {
                    my @a = split /$split_by/, $match;
                    map {
                        $out->{$_} = 1 if $_ ne '';
                    } @a;
                } else {
                    # treat the whole string as a single language identifier
                    $out->{$match} = 1;
                }
            }
        }
    }
}

# this goes through positive match rules and gathers the list of candidate languages
sub gather_languages {
    my ($self, $block, $file, $strref) = @_;

    my %found_languages;

    $self->_gather_from_rule($block->{file_matches}, $block->{then}->{split_by}, \$file, \%found_languages);
    $self->_gather_from_rule($block->{content_matches}, $block->{then}->{split_by}, $strref, \%found_languages);

    return sort keys %found_languages;
}

sub process_block {
    my ($self, $block, $file, $strref, $target_languages) = @_;

    sub _clear_languages {
        my ($href) = @_;
        map {
            delete $href->{$_};
        } keys %$href;
    }

    sub _include_languages {
        my ($href, $aref) = @_;
        map { $href->{$_} = 1 } @$aref;
    }

    sub _exclude_languages {
        my ($href, $aref) = @_;
        map { delete $href->{$_} } @$aref;
    }

    if ($self->check_block($block, $file, $strref)) {
        # ok, the rules are met, we can modify the list of languages
        my $then = $block->{then};

        # for `exclude_all_languages`, clear the list of target languages
        if ($then->{exclude_all_languages}) {
            _clear_languages($target_languages);
        }

        # for `include_all_languages`, expand the list to all target languages set in the job
        if ($then->{include_all_languages}) {
            _include_languages($target_languages, $self->{parent}->{original_destination_languages});
        }

        if (exists $then->{limit_languages}) {
            _clear_languages($target_languages);
            _include_languages($target_languages, $then->{limit_languages});
        }

        if (exists $then->{include_languages}) {
            _include_languages($target_languages, $then->{include_languages});
        }

        if (exists $then->{exclude_languages}) {
            _exclude_languages($target_languages, $then->{exclude_languages});
        }

        if ($then->{limit_to_matched_languages} ||
            $then->{include_matched_languages} ||
            $then->{exclude_matched_languages}) {

            my @matched_languages = $self->gather_languages($block, $file, $strref);

            print "[matched languages] ".join(', ', @matched_languages)."\n" if $self->{data}->{debug};

            if ($then->{limit_to_matched_languages}) {
                _clear_languages($target_languages);
                _include_languages($target_languages, \@matched_languages);
            }

            if ($then->{include_matched_languages}) {
                _include_languages($target_languages, \@matched_languages);
            }

            if ($then->{exclude_matched_languages}) {
                _exclude_languages($target_languages, \@matched_languages);
            }
        }

        # filter out languages that are completely not known to the job originally

        my %unknown_languages = %$target_languages;

        map {
            delete $unknown_languages{$_};
        } @{$self->{parent}->{original_destination_languages}};

        if (scalar(keys %unknown_languages) > 0) {
            foreach my $key (sort keys %unknown_languages) {
                delete $target_languages->{$key};
                print "[notice] removed language '$key' as not being on the target languages list\n" if $self->{data}->{debug};
            }
        }

        print "[target languages] ".join(', ', sort keys %$target_languages)."\n" if $self->{data}->{debug};

        # filter out languages that were already removed by the engine

        %unknown_languages = %$target_languages;

        map {
            delete $unknown_languages{$_};
        } @{$self->{parent}->{original_destination_languages}};

        map {
            delete $target_languages->{$_};
        } keys %unknown_languages;
    }
}

sub after_load_source_file_for_processing {
    my ($self, $phase, $file, $strref) = @_;

    # delete current values for that file, if any
    # (here we assume that each file's path for the given job is unique, and each file will go through this
    # callback phase and have its list of languages updated, so we don't care if the files' data persists
    # across multiple jobs)
    # TODO: make these two variables properties of $self

    delete $limitLanguages{$file};
    delete $orphaned{$file};

    my @j = @{$self->{parent}->{original_destination_languages}};
    my %limit_langs;
    @limit_langs{@j} = @j;

    foreach my $block (@{$self->{data}->{if}}) {
        $self->process_block($block, $file, $strref, \%limit_langs);
    }

    # a file is considered orphaned if the target list of destination languages is empty

    if (scalar(keys %limit_langs) == 0) {
        $orphaned{$file} = 1;
    }

    # save the final list of languages for the current file

    $limitLanguages{$file} = \%limit_langs;

    if (scalar(keys %limit_langs) != scalar @{$self->{parent}->{original_destination_languages}}) {
        if (scalar(keys %limit_langs) == 0) {
            print "\t\tNo destination languages\n";
        } else {
            print "\t\tDestination languages: ".join(', ', sort keys %limit_langs)."\n";
        }
    } else {
        print "\t\tAll destination languages\n";
    }
}

sub is_file_orphaned {
    my ($self, $phase, $file) = @_;

    return exists($orphaned{$file}) ? 1 : 0;
}

sub can_process_source_file {
    my ($self, $phase, $file) = @_;

    # do not allow to process orphaned files
    return 0 if exists($orphaned{$file});

    if (exists($limitLanguages{$file})) {
        my $l = $limitLanguages{$file};
        return (scalar(keys %$l) == 0) ? 0 : 1;
    } else {
        return 1; # by default, allow to process the source file
    }
}

sub can_process_file_lang {
    my ($self, $phase, $file, $lang) = @_;

    # do not allow to process orphaned files
    return 0 if exists($orphaned{$file});

    if (exists($limitLanguages{$file})) {
        my $l = $limitLanguages{$file};
        return exists($l->{$lang}) ? 1 : 0;
    } else {
        return 1; # by default, allow to process any files for any given target language
    }
}

1;