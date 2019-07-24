package Serge::Engine::Plugin::parse_go;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

# TODO:
# - Decode \\Uxxxx in strings

sub name {
    return '.go string map parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $translated_text;

    # Finding translatable strings in file

    # Format is:
    # ===================================================
    #
    # // optional single-line comment that is skipped, as it is followed by a blank line
    #
    # // optional comment that is treated as hint for the line below;
    # // multiple-line comments are supported
    # "some key": "value",
    #
    # // or
    # some_key: "value",
    #
    # // or
    # "some_key": `raw multi-line
    # string`,
    #
    # ===================================================
    # The key name is also appended to a hint message.
    # If the key contains '##suffix', the 'suffix' is used as a context string
    #
    # Limitations of a regexp-based parsing approach:
    # there must be no unpaired backticks inside strings. I.e. this string will break
    # the parsing:
    #
    # "`"

    my @all_hints;

    $$textref =~ s/`(.*?)`/'`'._replace_newlines($1).'`'/sge;

    foreach my $line (split(/\n/, $$textref)) {
        my $key;
        my $hint;
        my $context;
        my $orig_str;
        my $str;
        my $orig_str_for_subst;
        my $translated_str;
        my $wrapper_sym;

        if ($line =~ m/^\s*$/) { # blank line
            @all_hints = (); # reset accumulator array
        } elsif ($line =~ m/^\s*\/\/\s*(.*?)\s*$/) { # a [// comment] line
            push(@all_hints, $1);
        } elsif ($line =~ m/^\s*("(.*?)"|([\w\d]+))\s*:\s*"(.*)"\s*,\s*$/) { # a ["key": "value",] line
            $wrapper_sym = '"';
            $orig_str = $4;
            $str = _unescape($orig_str);
            $key = $2 || $3;
            ($hint, $context) = split(/##/, $key, 2);
            push(@all_hints, $hint) if $hint;

            if ($str ne '') {
                $translated_str = &$callbackref($str, $context, join("\n", @all_hints), undef, $lang, $key);
            }

            if ($translated_str ne '') {
                $translated_str = $wrapper_sym._escape($translated_str).$wrapper_sym;
            }

            @all_hints = ();
        } elsif ($line =~ m/^\s*("(.*?)"|([\w\d]+))\s*:\s*`(.*)`\s*,\s*$/) { # a ["key": `value`,] line
            $wrapper_sym = "`";
            $orig_str = $4;
            $str = _restore_newlines($orig_str);
            $key = $2 || $3;
            ($hint, $context) = split(/##/, $key, 2);
            push(@all_hints, $hint) if $hint;

            if ($str ne '') {
                $translated_str = &$callbackref($str, $context, join("\n", @all_hints), undef, $lang, $key);
            }

            if ($translated_str ne '') {
                $translated_str = $wrapper_sym.$translated_str.$wrapper_sym;
            }

            @all_hints = ();
        }

        if ($translated_str ne "") {
            $orig_str = $wrapper_sym.$orig_str.$wrapper_sym;
            $line =~ s/\Q$orig_str\E\s*,\s*$/$translated_str.','/e;
        }

        if ($lang) {
            $translated_text .= $line."\n";
        }
    }

    return $translated_text;
}

sub _replace_newlines {
    my $s = shift;
    $s =~ s/\n/\x01/g;
    return $s;
}

sub _restore_newlines {
    my $s = shift;
    $s =~ s/\x01/\n/g;
    return $s;
}

sub _unescape {
    my $s = shift;
    $s =~ s/\\u([0-9A-Fa-f]{4})/chr(hex($1))/ge; # decode \uXXXX
    $s =~ s/\\x([0-9A-Fa-f]{2})/chr(hex($1))/ge; # decode \xXX
    $s =~ s/\\"/"/g;
    $s =~ s/\\n/\n/g;
    $s =~ s/\\\\/\\/g;
    return $s;
}

sub _escape {
    my $s = shift;
    $s =~ s/\\/\\\\/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/"/\\"/g;
    return $s;
}

1;