package Serge::Engine::Plugin::test_language;
use parent Serge::Plugin::Base::Callback;

# Fake language used for testing purposes (i.e. "immediate translations").

use strict;
use warnings;

use Serge::Util qw(is_flag_set set_flags);

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
        transliterate     => 'BOOLEAN',
        expand_length     => 'BOOLEAN',
        translations => {
            '*'           => 'STRING'
        }
    });

    $self->add({
        get_translation_pre => \&get_translation,
        get_translation => \&get_translation,
        can_generate_ts_file => \&can_process_ts_file,
        can_process_ts_file => \&can_process_ts_file,
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    $self->{data}->{transliterate} = 1 unless exists $self->{data}->{transliterate};

    $self->{language} = exists $self->{data}->{language} ? $self->{data}->{language} : $LANG;
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
sub is_test_language {
    my ($self, $lang) = @_;
    return $lang eq $self->{language};
}

# private static method
sub _fake_translate_string {
    my ($self, $s) = @_;

    return $self->{data}->{translations}->{$s} if exists $self->{data}->{translations};

    my $out = $s;
    my $out_plaintext = $s;

    my $has_plurr_like_formatting = $s =~ m/\{[^\}]*\{/;

    if ($self->{data}->{transliterate} && !$has_plurr_like_formatting) {
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
        my $url = '(?:http|https|ftp|ssh):\/\/[\/\w\d\.\%\?\-\=\,\&\+\#\@]+';
        my $mailto = 'mailto:[\/\w\d\.\+\@]+';
        my @chunks = split(/($var|$sprintf|$escape|$php|$tag|$entity|$javafmt|$tplfmt|$unixpath|$url|$mailto)/, $s);

        $out = '';
        $out_plaintext = '';
        my $translate;
        foreach my $chunk (@chunks) {
            $translate = !$translate;

            if ($translate) {
                my @chars = split(//, $chunk);
                foreach my $char (@chars) {
                    $char = $map->{$char} || $char;
                    $out .= $char;
                    $out_plaintext .= $char;
                }
            } else {
                $out .= $chunk;
            }
        }

        # Substitute temporary markers back

        $out =~ s/__PHP__BLOCK__BEGIN__(.*?)__PHP__BLOCK__END__/'<?'._fake_translate_string_unescape($1).'?>'/ge;
    }

    # normalize plaintext string to see if it has

    $out_plaintext =~ s/\s{2,}/ /sg; # normalize whitespace
    $out_plaintext =~ s/^\s+//sg; # trim left
    $out_plaintext =~ s/\s+$//sg; # trim right

    $out = _expand_string($out) if $self->{data}->{expand_length} && $out_plaintext ne '';

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

sub _expand_string {
    my $s = shift;

    return $s if $s eq '';

    my $count = length($s);

    my $coeff = 1.4;
    $coeff = 1.5 if $count < 200;
    $coeff = 1.7 if $count < 20;
    $coeff = 2 if $count < 10;

    $count = int($count * ($coeff - 1));

    my $dummy_text = ' xxxxxxxxxx';
    # make sure dummy text length exceeds the needed number of chars to copy
    while (length($dummy_text) < $count) {
        $dummy_text .= $dummy_text;
    }

    my $start = '[';
    my $stop = ']';
    # if the source string already uses square brackets (for e.g. some sort of placeholders),
    # use parenthesis as markers instead
    if ($s =~ m/[\[\]]/) {
        $start = '(';
        $stop = ')';
    }

    return $start.$s.substr($dummy_text, 0, $count).$stop;
}

sub get_translation {
    my ($self, $phase, $string, $context, $namespace, $filepath, $lang) = @_;

    return () unless $self->is_test_language($lang);
    return ($self->_fake_translate_string($string), undef, undef, $self->{data}->{save_translations});
}

sub can_process_ts_file {
    my ($self, $phase, $file, $lang) = @_;

    # if this is a test language, do not import anything from translation file unless `save_translations' flag is on
    return 0 if $self->is_test_language($lang) && !$self->{data}->{save_translations};

    # by default, allow to process any translation files for any given target language
    return 1;
}

1;