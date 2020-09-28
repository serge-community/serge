package Serge::Engine::Plugin::parse_strings;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

sub name {
    return 'MacOS/iOS .strings parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $translated_text;

    # Finding translatable strings in file

    # Format is:
    # ===================================================
    #
    # /* optional single-line comment that is skipped, as it is followed by a blank line */
    #
    # /* optional single-line comment that is treated as hint for the line below */
    # "some key" = "value" // optional comment that is treated as additional hint
    # // or
    # some_key = "value" // optional comment that is treated as additional hint
    #
    # ===================================================
    # The key name is also appended to a hint message.
    # If the key contains '##suffix', the 'suffix' is used as a context string

    #               1           2                                   3               4
    $$textref =~ s/((?:^|\n)\h*("(?:\\"|[^"])+"|[\w\d\#]+)\h*=\h*")((?:\\"|[^"])*?)("\h*;)/$1.unwrap_string($3).$4/sge;

    my @all_hints;

    foreach my $line (split(/\n/, $$textref)) {

        my $key;
        my $hint;
        my $context;
        my $orig_str;
        my $translated_str;

        if ($line =~ m/^\h*$/) { # blank line
            @all_hints = (); # reset accumulator array
        } elsif ($line =~ m/^\h*\/\*\h*(.*?)\h*\*\/\h*$/) { # a /* */ comment line
            my $s = $1;
            if ($s && ($s !~ m/^Class = /)) {
                push(@all_hints, $s);
            }
        #                        1 2                3                  4            5       6
        } elsif ($line =~ m/^\h*("((?:\\"|[^"])+)"|([\w\d\#]+))\h*=\h*"(.*)"\h*;\h*(\/\/\h*(.*?))?$/) { # a "key"="value" line
            $orig_str = $4;
            push(@all_hints, $6) if $6;
            $key = unescape_string($2);
            $key = $3 if $key eq '';
            ($hint, $context) = split(/##/, $key, 2);

            # skip placeholder strings
            if ($orig_str =~ m/^Placeholder:/) {
                if ($lang) {
                    $translated_text .= $line."\n";
                }
                next;
            }
            push(@all_hints, $hint) if $hint;
        }

        if ($orig_str) {
            # remove all hint lines which are equal to the source string
            @all_hints = map { $_ eq $orig_str ? () : $_ } @all_hints;

            my $str = unescape_string($orig_str);

            $translated_str = &$callbackref($str, $context, join("\n", @all_hints), undef, $lang, $key);
            @all_hints = (); # reset accumulator array
        }

        if ($lang) {
            $translated_str = escape_string($translated_str);
            $line =~ s/\Q"$orig_str"\E[\t ]*;/"$translated_str";/;
            $translated_text .= $line."\n";
        }
    }

    return $translated_text;
}

sub unescape_string {
    my ($s) = @_;
    $s =~ s/\\\\/\000/g; # temporarily replace escaped backslashes with NULL chars
    $s =~ s/\\U([0-9A-Fa-f]{4})/chr(hex($1))/ge; # decode \UXXXX sequences
    $s =~ s/\\"/"/g;
    $s =~ s/\\n/\n/g;
    $s =~ s/\\r/\r/g;
    $s =~ s/\\t/\t/g;
    $s =~ s/\000/\\/g; # convert NULL characters to backslashes
    return $s;
}

sub escape_string {
    my ($s) = @_;
    $s =~ s/\\/\\\\/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/\r/\\r/g;
    $s =~ s/\t/\\t/g;
    $s =~ s/"/\\"/g;
    return $s;
}

sub unwrap_string {
    my ($s) = @_;
    $s =~ s/\n/\\n/sg;
    return $s;
}

1;