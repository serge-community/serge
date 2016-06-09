package Serge::Engine::Plugin::parse_plist;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

use Serge::Util qw(xml_escape_strref xml_unescape_strref);

sub name {
    return 'Mac OS .plist parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $translated_text = $$textref;

    # Format:
    # <key>...</key>
    # <string>...</string>

    $translated_text =~ s|(<key>([^<>]*?)</key>[\r\n\t ]*<string>)([^<>]*?)(</string>)|$1.$self->parse_callback($callbackref, $3, undef, $2, undef, $lang, $2).$4|sge;

    # Format:
    # <key>...</key>
    # <array>
    #     <string>...</string>
    #     <string>...</string>
    # </array>

    $translated_text =~ s|(<key>([^<>]*?)</key>[\r\n\t ]*<array>)(([\s]*<string>([^<>]*?)</string>[\s]*){1,})(</array>)|$1.$self->parse_array_callback($callbackref, $3, undef, $2, undef, $lang, $2).$6|sge;

    return $translated_text;
}

sub parse_array_callback {
    my ($self, $callbackref, $array_xml, $context, $hint, $flagsref, $lang, $key_prefix) = @_;
    my $n = 0;
    $array_xml =~ s|(<string>)([^<>]*?)(</string>)|$1.$self->parse_callback($callbackref, $2, $context, $hint, $flagsref, $lang, $key_prefix.'#'.$n++).$3|sge;
    return $array_xml;
}

sub parse_callback {
    my ($self, $callbackref, $string, $context, $hint, $flagsref, $lang, $key) = @_;

    xml_unescape_strref(\$string);

    my $translated_string = &$callbackref($string, $context, $hint, $flagsref, $lang, $key);

    $translated_string =~ s/\n/\\n/g;

    xml_escape_strref(\$translated_string);

    return $translated_string;
}

1;