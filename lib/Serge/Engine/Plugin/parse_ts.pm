package Serge::Engine::Plugin::parse_ts;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

no warnings qw(uninitialized);

use Serge::Util qw(full_locale_from_lang xml_escape_strref xml_unescape_strref);

sub name {
    return 'Qt Linguist TS parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $translated_text = $$textref;

    # Modify header

    # Example:
    # <TS version="2.0" language="en_US">

    $translated_text =~ s|(<TS .*? language=")(.*?)(">)|$1.&full_locale_from_lang($lang).$3|sgie;

    # Parse strings

    # Example:
    #   <source>Ok</source>
    #   <translation type="unfinished"></translation>

    if ($self->{import_mode}) {
        $translated_text =~ s|(<source>.*?</source>\s*<translation.*?>)(.*?)(</translation>)|$1.$self->parse_callback($callbackref, $2, undef, undef, undef, $lang).$3|sgie;
    } else {
        $translated_text =~ s|(<source>)(.*?)(</source>)(\s*)(<translation type="unfinished">)(</translation>)|$1.$2.$3.$4.'<translation>'.$self->parse_callback($callbackref, $2, undef, undef, undef, $lang).$6|sgie;
    }


    return $translated_text;
}

sub parse_callback {
    my ($self, $callbackref, $string, $context, $hint, $flagsref, $lang) = @_;

    xml_unescape_strref(\$string, undef, 1);

    my $translated_string = &$callbackref($string, $context, $hint, $flagsref, $lang);

    xml_escape_strref(\$translated_string, undef, 1);

    return $translated_string;
}

1;
