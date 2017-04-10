package Serge::Engine::Plugin::Transform::case;
use parent Serge::Engine::Plugin::Base::Transform;

use strict;

sub name {
    return 'Case normalization plugin';
}

sub filter_key {
    my ($self, $s) = @_;

    # Suppress `Operation "lc" returns its argument for UTF-16 surrogate 0xNNNN` warning
    # for the `lc()` call below; use 'utf8' instead of a more appropriate 'surrogate' pragma
    # since the latter is not available in until Perl 5.14
    no warnings 'utf8';

    return lc($s); # lowercase the string
}

sub transform {
    my ($self, $s, $target_string, $lang) = @_;

    $target_string =~ s/<.*?>//g;

    if (lc($target_string) eq $target_string) {
        # for German, always return the original string with unmodified case,
        # because in German all nouns start with the uppercase letter
        if ($lang =~ m/^(de|de-.*)$/) {
            return $s;
        } else {
            return lc($s);
        }
    }

    if (uc($target_string) eq $target_string) {
        return uc($s);
    }

    if (sc($target_string) eq $target_string) {
        # for German, uppercase only the first letter while leaving
        # all others intact
        if ($lang =~ m/^(de|de-.*)$/) {
            return sc_delicate($s);
        } else {
            return sc($s);
        }
    }

    # we don't want to apply title case anymore, since
    # it is not widely used outside the English language
    #if (tc($target_string) eq $target_string) {
    #    return tc($s);
    #}

    # TODO: do the same but in XML-aware fashion, by skipping the tags
    # ...

    # TODO: do the same but skip the %PLACEHOLDERS%
    # ...

    # TODO: do the same but skip the {PLACEHOLDERS}
    # ...

    # TODO: do the same but skip the {{PLACEHOLDERS}}
    # ...

    # TODO: do the same but skip the {{{PLACEHOLDERS}}}
    # ...

    # TODO: do the same but skip the sfprinf-style strings
    # ...

    # ...
    # ...

    return $s;
}

# Uppercase the first letter, lowercase everything else.
# Note: not an object's method
sub sc {
    my $s = lc(shift);
    $s = uc(substr($s, 0, 1)) . substr($s, 1);
}

# Uppercase the first letter, leave everything else intact
# Note: not an object's method
sub sc_delicate {
    my $s = shift;
    $s = uc(substr($s, 0, 1)) . substr($s, 1);
}

# Apply title case (uppercase the first letter of each word, lowercase everything else).
# Note: not an object's method
sub tc {
    my $s = lc(shift);
    $s =~ s/(\W)(\w)/$1.uc($2)/sge;
    $s =~ s/^(\W*)(\w)/$1.uc($2)/sge;
    return $s;
}

1;