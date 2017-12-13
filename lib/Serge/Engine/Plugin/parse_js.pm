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
    #   "key" : "value",
    #   "key":"value",
    #   "key": "value", // comment

    $translated_text =~ s!^(\h*")(.+?)("\h*:\h*")((?:\\\\|\\"|[^"])+?)("\h*(?:,\h*)?(?://\h*(.*)\h*)?)$!$1.$2.$3.$self->parse_callback($callbackref, $4, undef, $2, $6, $lang).$5!mgie;

    return $translated_text;
}

sub parse_callback {
    my ($self, $callbackref, $string, $context, $key, $comment, $lang) = @_;

    my @hint;
    push @hint, $key if $key ne '' && $key ne $string;
    push @hint, $comment if $comment ne '';

    $string =~ s/\\"/"/g;
    $string =~ s/\\\\/\\/g;

    my $translated_string = &$callbackref($string, $context, join("\n", @hint), undef, $lang, $key);

    $translated_string =~ s/\\/\\\\/g;
    $translated_string =~ s/\n/\\n/sg;
    $translated_string =~ s/"/\\"/g;

    return $translated_string;
}

1;