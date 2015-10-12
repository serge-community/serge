package Serge::Engine::Plugin::parse_dtd;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

sub name {
    return '.dtd entities parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    # Finding translatable strings in file

    # Format is:
    # <!ENTITY hint "text">

    my $translated_text = $$textref;

    $translated_text =~ s|(<!ENTITY\s+)([\w\-\.]+)(\s*"\s*)(.*?)(\s*"\s*>)|$1.$2.$3.$self->parse_callback($callbackref, $4, undef, $2, undef, $lang, $2).$5|sgie;

    return $translated_text;
}

sub parse_callback {
    my ($self, $callbackref, $string, $context, $hint, $flagsref, $lang, $key) = @_;

    $string =~ s/&apos;/'/g;
    $string =~ s/&quot;/"/g;
    $string =~ s/&#34;/"/g;
    $string =~ s/&#35;/#/g;
    $string =~ s/&#38;/&/g;

    my $translated_string = &$callbackref($string, $context, $hint, $flagsref, $lang, $key);

    $translated_string =~ s/\#/__HASH__/g;
    $translated_string =~ s/\&/__AMP__/g;
    $translated_string =~ s/\'/&apos;/g;
    $translated_string =~ s/\"/&#34;/g;
    $translated_string =~ s/__HASH__/&#35;/g;
    $translated_string =~ s/__AMP__/&#38;/g;

    return $translated_string;
}

1;