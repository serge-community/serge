package Serge::Engine::Plugin::parse_strings;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

# TODO:
# - Decode \\Uxxxx in strings
# - Support "key" = "value" pairs that span multiple lines
# - Better handling of comments

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

    my @all_hints;

    foreach my $line (split(/\n/, $$textref)) {

        my $key;
        my $hint;
        my $context;
        my $orig_str;
        my $translated_str;

        if ($line =~ m/^[\t ]*$/) { # blank line
            @all_hints = (); # reset accumulator array
        } elsif ($line =~ m/^[\t ]*\/\*[\t ]*(.*?)[\t ]*\*\/[\t ]*$/) { # a /* */ comment line
            my $s = $1;
            if ($s && ($s !~ m/^Class = /)) {
                push(@all_hints, $s);
            }
        } elsif ($line =~ m/^[\t ]*("(.*?)"|([\w\#]+))[\t ]*=[\t ]*"(.*)"[\t ]*;[\t ]*(\/\/[\t ]*(.*?))?$/) { # a "key"="value" line
            $orig_str = $4;
            push(@all_hints, $6) if $6;
            $key = $2 || $3;
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

            my $str = $orig_str;
            $str =~ s/\\"/"/g;
            $str =~ s/\\n/\n/g;
            $str =~ s/\\\\/\\/g;

            $translated_str = &$callbackref($str, $context, join("\n", @all_hints), undef, $lang, $key);
            @all_hints = (); # reset accumulator array
        }

        if ($lang) {
            $translated_str =~ s/\\/\\\\/g;
            $translated_str =~ s/\n/\\n/g;
            $translated_str =~ s/"/\\"/g;
            $line =~ s/\Q"$orig_str"\E[\t ]*;/"$translated_str";/;
            $translated_text .= $line."\n";
        }
    }

    return $translated_text;
}

1;