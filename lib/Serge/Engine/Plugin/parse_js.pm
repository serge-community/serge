package Serge::Engine::Plugin::parse_js;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

our $VERSION = 2;

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

    #   'key': 'value',
    #   'key': "value",
    #   "key": 'value',

    #   key: "value",
    #   key: 'value',

    #   key: `value`,

    # \h = horizontal whitespace
    #                       1   23                   4            5  6                      7  8                      9  10 11                  12
    $translated_text =~ s!^(\h*((['"]).+?\3|[\w\d]+)(\h*:\h*))(?:(")((?:\\\\|\\"|[^"])+?)"|(')((?:\\\\|\\'|[^'])+?)'|(`)((?:\\\\|\\`|[^`])+?)`)(\h*(?:,\h*)?(?://\h*(.*)\h*)?)$!$1.$5.$7.$9.$self->parse_callback($callbackref, $6.$8.$10, undef, $2, $12, $lang).$5.$7.$9.$11!mgie;

    return $translated_text;
}

sub parse_callback {
    my ($self, $callbackref, $string, $context, $key, $comment, $lang) = @_;

    my @hint;

    # remove surrounding quotes, if any
    if ($key =~m/^(['"])(.+?)\1$/) {
        $key = $2;
    }

    push @hint, $key if $key ne '' && $key ne $string;
    push @hint, $comment if $comment ne '';

    $string =~ s/(\\\d{1,3}|\\x[0-9a-f]{2}|\\u[0-9a-f]{4}|\\u\{[0-9a-f]{1,6}\}|\\[bfnrtv"'\\\/])/_unescape($1)/sgie;

    my $translated_string = &$callbackref($string, $context, join("\n", @hint), undef, $lang, $key);

    $translated_string =~ s/(\\[bfrv\/]|[\\"'\n\t])/_escape($1)/sge;

    return $translated_string;
}

sub _unescape {
    my $s = shift;
    $s eq '\\n' && return "\n";
    $s eq '\\t' && return "\t";

    if ($s =~ m/^\\(\d{1,3})$/) {
        return chr oct $1;
    }

    if ($s =~ m/^\\x([0-9a-f]{2})$/i) {
        return chr hex $1;
    }

    if ($s =~ m/^\\u([0-9a-f]{4})$/i) {
        return chr hex $1;
    }

    if ($s =~ m/^\\u\{([0-9a-f]{1,6})\}$/i) {
        return chr hex $1;
    }

    if ($s =~ m/^\\[bfrv]$/i) {
        return $s;
    }

    $s =~ s/^\\//;
    return $s;
}

sub _escape {
    my $s = shift;
    $s eq "\n" && return '\n';
    $s eq "\t" && return '\t';
    if ($s =~ m/^\\[bfrv]$/i) {
        return $s;
    }
    return '\\'.$s;
}

1;