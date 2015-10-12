package Serge::Engine::Plugin::parse_key_space_value;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

sub name {
    return 'Plain key<_space_>value string parser';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $translated_text = $$textref;

    # Finding translatable strings in file

    # Format is:
    #   key value
    #   key\tvalue
    # (leading and trailing whitespaces are preserved but are not extracted as a string or as a hint)

    #                       $1   $2   $3   $4   $5
    $translated_text =~ s|^(\s*)(\S+)(\s+)(.+?)(\s*)$|$1.$2.$3.$self->parse_callback($callbackref, $4, undef, $2, undef, $lang).$5|mgie;

    return $translated_text;
}

sub parse_callback {
    my ($self, $callbackref, $string, $context, $hint, $flagsref, $lang) = @_;

    my $translated_string = &$callbackref($string, $context, $hint, $flagsref, $lang);

    $translated_string =~ s/\n/\\n/sg;

    return $translated_string;
}

1;