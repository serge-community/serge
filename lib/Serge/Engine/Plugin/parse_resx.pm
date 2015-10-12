package Serge::Engine::Plugin::parse_resx;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

use Serge::Util qw(xml_escape_strref xml_unescape_strref);

sub name {
    return '.Net .resx parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    # Finding translatable strings in file

    # Format is:
    # <data name="...hint..." ...>
    #   <value>...string...</value>
    # </data>

    my $translated_text = $$textref;

    $translated_text =~ s|(<data.*?name=")(.*?)(".*?>.*?<value[^\/]*?>)(.*?)(</value>)|$1.$2.$3.$self->parse_callback($callbackref, $4, undef, $2, undef, $lang).$5|sge;

    return $translated_text;
}

sub parse_callback {
    my ($self, $callbackref, $string, $context, $hint, $flagsref, $lang) = @_;

    xml_unescape_strref(\$string);

    my $translated_string = &$callbackref($string, $context, $hint, $flagsref, $lang);

    xml_escape_strref(\$translated_string);

    return $translated_string;
}

1;