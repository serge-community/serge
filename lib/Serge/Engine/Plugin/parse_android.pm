package Serge::Engine::Plugin::parse_android;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

no warnings qw(uninitialized);

sub name {
    return 'Android strings.xml parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    # Finding translatable strings in file

    # Format is:
    #
    # <string name="...hint..." ...>...string...</string>
    #
    # or:
    #
    # <string-array name="...hint..." ...>
    #   <item>...string...</item>
    #   ...
    # </string-array>
    #
    # or:
    #
    # <plurals name="...hint1..." ...>
    #   <item quantity="...hint2...">...string...</item>
    #   ...
    # </plurals>

    my $translated_text = $$textref;

    $translated_text =~ s|(<string [^\/\<\>]*?>)(.*?)(</string>)|$1.$self->parse_string_callback($callbackref, $1, $2, $lang).$3|sge;
    $translated_text =~ s|(<plurals [^\/\<\>]*?>)(.*?)(</plurals>)|$1.$self->parse_plurals_callback($callbackref, $1, $2, $lang).$3|sge;
    $translated_text =~ s|(<string-array [^\/\<\>]*?>)(.*?)(</string-array>)|$1.$self->parse_string_array_callback($callbackref, $1, $2, $lang).$3|sge;

    return $translated_text;
}

sub parse_string_callback {
    my ($self, $callbackref, $opening_tag, $inner_xml, $lang) = @_;

    return $inner_xml if $opening_tag =~ m|\btranslatable="false"|;
    my $key = $1 if $opening_tag =~ m|\bname="(.*?)"|;

    return $self->parse_callback($callbackref, $inner_xml, undef, $key, undef, $lang, $key);
}

sub parse_plurals_callback {
    my ($self, $callbackref, $opening_tag, $inner_xml, $lang) = @_;

    return $inner_xml if $opening_tag =~ m|\btranslatable="false"|;
    my $key = $1 if $opening_tag =~ m|\bname="(.*?)"|;

    $inner_xml =~ s|(<item .*?quantity=")(.*?)(".*?>)(.*?)(</item>)|$1.$2.$3.$self->parse_callback($callbackref, $4, undef, "$key:$2", undef, $lang, "$key:$2").$5|sge;
    return $inner_xml;
}

sub parse_string_array_callback {
    my ($self, $callbackref, $opening_tag, $inner_xml, $lang) = @_;

    return $inner_xml if $opening_tag =~ m|\btranslatable="false"|;
    my $key = $1 if $opening_tag =~ m|\bname="(.*?)"|;

    my $index = 0;
    $inner_xml =~ s|(<item>)(.*?)(</item>)|$1.$self->parse_callback($callbackref, $2, undef, "$key:item", undef, $lang, $key.':'.$index++).$3|sge;
    return $inner_xml;
}

sub process_non_xml_chunks {
    my ($s, $callback) = @_;

    my @chunks = split(/(<.*?>)/, $s);
    my $out = '';
    my $translate;

    foreach my $chunk (@chunks) {
        $translate = !$translate;
        &$callback(\$chunk) if $translate;
        $out .= $chunk;
    }
    return $out;
}

sub unescape_callback {
    my $strref = shift;

    $$strref =~ s/\\'/'/g; # Android-specific apostrophe unescaping
    $$strref =~ s/\\"/"/g; # Android-specific quote unescaping
}

sub escape_callback {
    my $strref = shift;

    $$strref =~ s/'/\\'/g; # Android-specific apostrophe escaping
    $$strref =~ s/"/\\"/g; # Android-specific quote escaping
}

sub parse_callback {
    my ($self, $callbackref, $string, $context, $hint, $flagsref, $lang, $key) = @_;

    $string = process_non_xml_chunks($string, \&unescape_callback);

    my $translated_string = &$callbackref($string, $context, $hint, $flagsref, $lang, $key);

    $translated_string = process_non_xml_chunks($translated_string, \&escape_callback);

    return $translated_string;
}

1;