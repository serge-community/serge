package Serge::Engine::Plugin::parse_js;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

sub name {
    return 'Generic JavaScript object parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $translated_text = $$textref;

    # Parse strings

    # Example:
    #   "key" : "value"
    #   "key":"value"

    $translated_text =~ s|^(\s*")(.+?)("\s*:\s*")(.+)("\s*(,\s*)?)$|$1.$2.$3.$self->parse_callback($callbackref, $4, undef, $2, undef, $lang).$5|mgie;

    return $translated_text;
}

sub parse_callback {
    my ($self, $callbackref, $string, $context, $hint, $flagsref, $lang) = @_;

    $string =~ s/\\"/"/g;
    $string =~ s/\\\\/\\/g;

    my $translated_string = &$callbackref($string, $context, $hint, $flagsref, $lang);

    $translated_string =~ s/\\/\\\\/g;
    $translated_string =~ s/\n/\\n/sg;
    $translated_string =~ s/"/\\"/g;

    return $translated_string;
}

1;