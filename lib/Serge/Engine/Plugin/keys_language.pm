package Serge::Engine::Plugin::keys_language;
use parent Serge::Plugin::Base::Callback;

# Generate localized resources with unique string key being the translation value

use strict;
use warnings;

use Serge::Util qw(generate_hash is_flag_set set_flags);

our $SEED_WITH_STRING = undef; # default `seed_with_string` value
our $STRING_FORMAT = '%HASH%'; # default `string_format` value
our $HINT_FORMAT = '%HASH%'; # default `hint_format` value
our $LANG = 'keys'; # default `language` value

sub name {
    return 'Language translation provider which generates unique string keys as translation values';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        save_translations => 'BOOLEAN',
        language          => 'STRING',
        seed              => 'STRING',
        seed_with_string  => 'BOOLEAN',
        string_format     => 'STRING',
        hint_format       => 'STRING',
        translations => {
            '*'           => 'STRING'
        }
    });

    $self->add({
        add_hint => \&add_hint,
        get_translation_pre => \&get_translation,
        get_translation => \&get_translation,
        can_generate_ts_file => \&can_process_ts_file,
        can_process_ts_file => \&can_process_ts_file,
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    my $d = $self->{data};
    $self->{language} = exists $d->{language} ? $d->{language} : $LANG;
    $self->{string_format} = exists $d->{string_format} ? $d->{string_format} : $STRING_FORMAT;
    $self->{hint_format} = exists $d->{hint_format} ? $d->{hint_format} : $HINT_FORMAT;
    $self->{seed_with_string} = exists $d->{seed_with_string} ? $d->{seed_with_string} : $SEED_WITH_STRING;

    if ($self->{string_format} !~ m/%HASH%/) {
        die "`format` parameter value must have a %HASH% macro"
    }

    if ($self->{hint_format} !~ m/%HASH%/) {
        die "`format` parameter value must have a %HASH% macro"
    }
}

sub adjust_phases {
    my ($self, $phases) = @_;

    $self->SUPER::adjust_phases($phases);

    # always tie to 'can_process_ts_file' phase
    set_flags($phases, 'can_generate_ts_file', 'can_process_ts_file');

    # this plugin makes sense only when applied to either
    # get_translation_pre or get_translation phase, but not both
    my $f1 = is_flag_set($phases, 'get_translation_pre');
    my $f2 = is_flag_set($phases, 'get_translation');
    die "This plugin needs to be attached to either get_translation_pre or get_translation phase" if !$f1 && !$f2;
    die "This plugin needs to be attached to either get_translation_pre or get_translation phase, but not both" if $f1 && $f2;
}

# public static method
sub is_keys_language {
    my ($self, $lang) = @_;
    return $lang eq $self->{language};
}

sub generate_raw_key {
    my ($self, $namespace, $filepath, $source_key, $string, $context) = @_;

    my @a = ($self->{data}->{seed}, $namespace, $filepath);
    if (defined $source_key && $source_key ne '') {
        # when source key is defined, use it as a string identifier
        push @a, $source_key;
        if ($self->{seed_with_string}) {
            # optionally, add the string itself, which ensures that the key
            # changes if the same source key is reused for a different value
            push @a, $string;
        }
    } else {
        # if no source key is present, use a combination of string and context
        # as a unique string identifier within a file
        push @a, ($string, $context);
    }

    return generate_hash(@a);
}

sub add_hint {
    my ($self, $phase, $string, $context, $namespace, $filepath, $source_key, $lang, $aref) = @_;

    my $hash = $self->generate_raw_key($namespace, $filepath, $source_key, $string, $context);
    my $hint = $self->{hint_format};
    $hint =~ s/%HASH%/$hash/sg;

    push @$aref, $hint;
}

sub get_translation {
    my ($self, $phase, $string, $context, $namespace, $filepath, $lang, $disallow_similar_lang, $item_id, $source_key) = @_;

    return () unless $self->is_keys_language($lang);
    my $hash = $self->generate_raw_key($namespace, $filepath, $source_key, $string, $context);
    my $key = $self->{string_format};
    $key =~ s/%HASH%/$hash/sg;

    return ($key, undef, undef, $self->{data}->{save_translations}) if $self->is_keys_language($lang);
    return (); # otherwise, return an empty array
}

sub can_process_ts_file {
    my ($self, $phase, $file, $lang) = @_;

    # if this is a key language, do not import anything from translation file unless `save_translations' flag is on
    return 0 if $self->is_keys_language($lang) && !$self->{data}->{save_translations};

    # by default, allow to process any translation files for any given target language
    return 1;
}

1;