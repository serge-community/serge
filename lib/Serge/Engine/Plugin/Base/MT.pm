package Serge::Engine::Plugin::Base::MT;
use parent Serge::Plugin::Base::Callback;

use strict;
use warnings;
use utf8;

use Serge::Util qw(is_flag_set set_flags);

sub name {
    return 'Base MT provider';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        target_languages   => 'ARRAY',
        post_edit          => 'BOOLEAN',
        as_fuzzy_default   => 'BOOLEAN',
        as_fuzzy           => 'ARRAY',
        as_not_fuzzy       => 'ARRAY',
        lang_rewrite       => {
            '*'            => 'STRING',
        }
    });

    $self->add({
        get_translation => \&get_translation,
        can_generate_ts_file => \&can_process_ts_file,
        can_process_ts_file => \&can_process_ts_file,
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    $self->{data}->{post_edit} = 1 unless exists $self->{data}->{post_edit};
    $self->{data}->{as_fuzzy_default} = 1 unless exists $self->{data}->{as_fuzzy_default};
}

sub adjust_phases {
    my ($self, $phases) = @_;

    $self->SUPER::adjust_phases($phases);

    # always tie to these phases
    set_flags($phases, 'get_translation', 'can_generate_ts_file', 'can_process_ts_file');
}

sub mt_get_translation {
    my ($self, $src_lang, $target_lang, $s) = @_;
    die "Please define your mt_get_translation method";
}

sub is_language_supported {
    my ($self, $lang) = @_;

    if (exists $self->{data}->{target_languages}) {
        return undef unless is_flag_set($self->{data}->{target_languages}, $lang);
    }
    return 1;
}

sub get_translation {
    my ($self, $phase, $string, $context, $namespace, $filepath, $lang) = @_;

    return () unless $self->is_language_supported($lang);

    my $src_lang = $self->{parent}->{source_language};

    my $lr = $self->{data}->{lang_rewrite};
    if (defined $lr) {
        if (exists $lr->{$src_lang}) {
            $src_lang = $lr->{$src_lang};
        }
        if (exists $lr->{$lang}) {
            $lang = $lr->{$lang};
        }
    }

    my $max_len = 10;
    my $trimmed_s = length($string) > $max_len ? substr($string, 0, $max_len-1).'…' : $string;
    print "[MT] Requesting $src_lang->$lang translation for '$trimmed_s'\n";# if $self->{parent}->{debug};

    my $translation = $self->mt_get_translation($src_lang, $lang, $string);
    return () unless defined $translation;

    my $as_fuzzy = is_flag_set($self->{data}->{as_fuzzy}, $lang);
    my $as_not_fuzzy = is_flag_set($self->{data}->{as_not_fuzzy}, $lang);
    my $fuzzy = 1 if $as_fuzzy || ($self->{data}->{as_fuzzy_default} && !$as_not_fuzzy);

    return ($translation, $fuzzy, undef, 1);
}

sub can_process_ts_file {
    my ($self, $phase, $file, $lang) = @_;

    # otherwise, allow to process translation files
    # if the language is not supported
    return 1 unless $self->is_language_supported($lang);

    # if post editing is turned off, do not import anything
    # from translation files
    return 0 if !$self->{data}->{post_edit};

    # otherwise, allow to process translation files
    return 1;
}

1;