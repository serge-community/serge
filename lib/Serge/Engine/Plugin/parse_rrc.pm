package Serge::Engine::Plugin::parse_rrc;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

# TODO:
# - Decode \\Uxxxx in strings
# - Support "key" = "value" pairs that span multiple lines
# - Better handling of comments

sub name {
    return 'Blackberry .rrc parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $translated_text;

    # Finding translatable strings in file

    # Format is: key = "value"

    foreach my $line (split(/\n/, $$textref)) {

        my $hint;
        my $context;
        my $orig_str;
        my $translated_str;

        if ($line =~ m/^[\t ]*(.*?)#0[\t ]*=[\t ]*"(.*)";$/) {
            $hint = $1;
            $orig_str = $2;
        }

        if ($orig_str) {
            my $str = $orig_str;
            $str =~ s/\\"/"/g;
            $str =~ s/\\n/\n/g;
            $str =~ s/\\\\/\\/g;
            $translated_str = &$callbackref($str, $context, $hint, undef, $lang);
        }

        if ($lang) {
            $translated_str =~ s/\\/\\\\/g;
            $translated_str =~ s/\n/\\n/g;
            $translated_str =~ s/"/\\"/g;
            $line =~ s/\Q"$orig_str";\E/"$translated_str";/;
            $translated_text .= $line."\n";
        }
    }

    return $translated_text;
}

1;