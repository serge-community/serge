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
    my $hint = $1 if $opening_tag =~ m|\bname="(.*?)"|;

    return $self->parse_callback($callbackref, $inner_xml, undef, $hint, undef, $lang);
}

sub parse_plurals_callback {
    my ($self, $callbackref, $opening_tag, $inner_xml, $lang) = @_;

    return $inner_xml if $opening_tag =~ m|\btranslatable="false"|;
    my $hint = $1 if $opening_tag =~ m|\bname="(.*?)"|;

    $inner_xml =~ s|(<item .*?quantity=")(.*?)(".*?>)(.*?)(</item>)|$1.$2.$3.$self->parse_callback($callbackref, $4, undef, "$hint:$2", undef, $lang).$5|sge;
    return $inner_xml;
}

sub parse_string_array_callback {
    my ($self, $callbackref, $opening_tag, $inner_xml, $lang) = @_;

    return $inner_xml if $opening_tag =~ m|\btranslatable="false"|;
    my $hint = $1 if $opening_tag =~ m|\bname="(.*?)"|;

    $inner_xml =~ s|(<item>)(.*?)(</item>)|$1.$self->parse_callback($callbackref, $2, undef, "$hint:item", undef, $lang).$3|sge;
    return $inner_xml;
}

sub parse_callback {
    my ($self, $callbackref, $string, $context, $hint, $flagsref, $lang) = @_;

    $string =~ s/\\'/'/g; # Android-specific apostrophe unescaping
    $string =~ s/\\"/"/g; # Android-specific quote unescaping

    my $translated_string = &$callbackref($string, $context, $hint, $flagsref, $lang);

    $translated_string =~ s/'/\\'/g; # Android-specific apostrophe escaping
    $translated_string =~ s/"/\\"/g; # Android-specific quote escaping

    return $translated_string;
}

1;