package Serge::Engine::Plugin::test_language;
use parent Serge::Plugin::Base::Callback;

# Fake language used for testing purposes (i.e. "immediate translations").

use strict;
use warnings;

use Serge::Util qw(set_flag);

our $LANG = 'test';
our $LANGID = 0xffff;

sub name {
    return 'Test (fake) language translation provider';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        save_translations => 'BOOLEAN',
        language          => 'STRING',
        translations => {
            '*'           => 'STRING'
        }
    });

    $self->add({
        get_translation_pre => \&get_translation,
        get_translation => \&get_translation,
        can_process_ts_file => \&can_process_ts_file,
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    $self->{language} = exists $self->{data}->{language} ? $self->{data}->{language} : $LANG;
}

sub adjust_phases {
    my ($self, $phases) = @_;

    $self->SUPER::adjust_phases($phases);

    # always tie to 'can_process_ts_file' phase
    set_flag($phases, 'can_process_ts_file');

    # this plugin makes sense only when applied to a single phase (in addition to 'can_process_ts_file')
    die "This plugin needs to be attached to only one phase at a time" unless @$phases == 2;
}

# public static method
sub is_test_language {
    my ($self, $lang) = @_;
    return $lang eq $self->{language};
}

# private static method
sub _fake_translate_string {
    my ($self, $s) = @_;

    return $self->{data}->{translations}->{$s} if exists $self->{data}->{translations};

    # Map English alphabet to similarly looking Unicode symbols with accents, umlauts, etc.

    my $map = {
        'A' => "\x{100}",   'B' => "\x{1e02}",  'C' => "\x{106}",   'D' => "\x{110}",
        'E' => "\x{112}",   'F' => "\x{1e1e}",  'G' => "\x{11c}",   'H' => "\x{124}",
        'I' => "\x{128}",   'J' => "\x{134}",   'K' => "\x{136}",   'L' => "\x{141}",
        'M' => "\x{1e3e}",  'N' => "\x{145}",   'O' => "\x{150}",   'P' => "\x{1e54}",
        'Q' => "\x{3a9}",   'R' => "\x{156}",   'S' => "\x{160}",   'T' => "\x{166}",
        'U' => "\x{16e}",   'V' => "\x{1e7c}",  'W' => "\x{174}",   'X' => "\x{4b2}",
        'Y' => "\x{176}",   'Z' => "\x{17d}",   'a' => "\x{e1}",    'b' => "\x{1e03}",
        'c' => "\x{e7}",    'd' => "\x{111}",   'e' => "\x{113}",   'f' => "\x{1e1f}",
        'g' => "\x{11f}",   'h' => "\x{125}",   'i' => "\x{129}",   'j' => "\x{135}",
        'k' => "\x{137}",   'l' => "\x{13c}",   'm' => "\x{1e3f}",  'n' => "\x{14b}",
        'o' => "\x{151}",   'p' => "\x{1e55}",  'q' => "\x{1eb}",   'r' => "\x{155}",
        's' => "\x{161}",   't' => "\x{163}",   'u' => "\x{169}",   'v' => "\x{1e7d}",
        'w' => "\x{175}",   'x' => "\x{4b3}",   'y' => "\x{177}",   'z' => "\x{17e}"
    };

    # As PHP blocks can be inside tags, substitute them to ease parsing
    $s =~ s/<\?(.*?)\?>/'__PHP__BLOCK__BEGIN__'._fake_translate_string_escape($1).'__PHP__BLOCK__END__'/ge;

    my $sprintf = '%[-+]*[0 #]*[\d]*(?:.\d+)*(?:h|l|I|I32|I64)*[cCdiouxXeEfgGnsS]';
    my $escape = '\\\\[ntvbrfax]'; # '\' is double-escaped
    my $var = '%(?:\w+:)*\w+(?:&\w)*%';
    my $tag = '<[^\?]>|<[^\?].*?[^\?]>'; # do not count <? and ?> inside tags
    my $php = '__PHP__BLOCK__BEGIN__.*?__PHP__BLOCK__END__';
    my $entity = '\&(?:\w+);';
    my $javafmt = '\{\d+\}';
    my $tplfmt = '\$\{.+?\}';
    my $unixpath = '(?:^|[\/\r\n\t ]+)(?:\/[\w\d\.\%\?\-\=\,\&]+)+';
    my @chunks = split(/($var|$sprintf|$escape|$php|$tag|$entity|$javafmt|$tplfmt|$unixpath)/, $s);

    my $out;
    my $translate;
    foreach my $chunk (@chunks) {
        $translate = !$translate;

        if ($translate) {
            my @chars = split(//, $chunk);
            foreach my $char (@chars) {
                my $c = $map->{$char};
                $out .= $c ? $c : $char;
            }
        } else {
            $out .= $chunk;
        }
    }

    # Substitute temporary markers back

    $out =~ s/__PHP__BLOCK__BEGIN__(.*?)__PHP__BLOCK__END__/'<?'._fake_translate_string_unescape($1).'?>'/ge;

    return $out;
}

sub _fake_translate_string_escape {
    my $s = shift;

    $s =~ s/</__LESS__THAN__/g;
    $s =~ s/>/__GREATER__THAN__/g;

    return $s;
}

sub _fake_translate_string_unescape {
    my $s = shift;

    $s =~ s/__LESS__THAN__/</g;
    $s =~ s/__GREATER__THAN__/>/g;

    return $s;
}

sub get_translation {
    my ($self, $phase, $string, $context, $namespace, $filepath, $lang, $disallow_similar_lang, $item_id) = @_;

    return ($self->_fake_translate_string($string), undef, undef, $self->{data}->{save_translations}) if $self->is_test_language($lang);
    return (); # otherwise, return an empty array
}

sub can_process_ts_file {
    my ($self, $phase, $file, $lang) = @_;

    # if this is a test language, do not import anything from translation file unless `save_translations' flag is on
    return 0 if $self->is_test_language($lang) && !$self->{data}->{save_translations};

    # by default, allow to process any .po files for any given target language
    return 1;
}

1;