package Serge::Engine::Plugin::parse_hash;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

sub name {
    return "Perl/PHP/Ruby Associative Array (Hash) Parser Plugin";
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $translated_text = $$textref;

    # Finding translatable strings in file

    # Format is:
    #   'key' => 'value',

    $translated_text =~ s|^(\s*')(.+?)('\s*=>\s*')(.+)('(,\s*)?)$|$1.$2.$3.$self->parse_callback($callbackref, $4, undef, $2, undef, $lang).$5|mgie;

    return $translated_text;
}

sub parse_callback {
    my ($self, $callbackref, $string, $context, $hint, $flagsref, $lang) = @_;

    $string =~ s/\\n/\n/sg;
    $string =~ s/\\'/'/sg;
    $string =~ s/\\\\/\\/sg;

    my $translated_string = &$callbackref($string, $context, $hint, $flagsref, $lang);

    $translated_string =~ s/\\/\\\\/sg;
    $translated_string =~ s/'/\\'/sg;
    $translated_string =~ s/\n/\\n/sg;

    return $translated_string;
}

1;