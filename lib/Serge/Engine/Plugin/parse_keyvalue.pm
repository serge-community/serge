package Serge::Engine::Plugin::parse_keyvalue;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

sub name {
    return 'Plain key=value string parser';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $translated_text = $$textref;

    # Finding translatable strings in file

    # Format is:
    #   key=value
    #   key = value

    $translated_text =~ s|^(.+?)(\s*=\s*)(.+)$|$1.$2.$self->parse_callback($callbackref, $3, undef, $1, undef, $lang)|mgie;

    return $translated_text;
}

sub parse_callback {
    my ($self, $callbackref, $string, $context, $hint, $flagsref, $lang) = @_;

    my $translated_string = &$callbackref($string, $context, $hint, $flagsref, $lang, $hint);

    $translated_string =~ s/\n/\\n/sg;

    return $translated_string;
}

1;