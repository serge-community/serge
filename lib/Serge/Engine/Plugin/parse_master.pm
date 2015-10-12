package Serge::Engine::Plugin::parse_master;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

no warnings qw(uninitialized);

sub name {
    return 'Master files parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    # Finding translatable strings in file

    # Format is: <%string%>
    #        or: <%string%%context%>
    #        or: <%string%%context%%hint%>
    #        or: <%string%%context%%hint%%flags%>
    # context, hint and flags are optional and can be empty:
    #            <%string%%%%hint%>
    #            <%string%%%%%%flags%>

    if ($lang) {
        # do a substitution (on a copy of the string)
        my $translated_text = $$textref;
        $translated_text =~ s|<%(.*?)%>|&$callbackref(_split_params($1), $lang)|sge;
        return $translated_text;
    } else {
        # just match strings (faster)
        while ($$textref =~ m/<%(.*?)%>/sg) { &$callbackref(_split_params($1), undef); }
        return undef;
    }
}

sub _split_params {
    my ($str, $context, $hint, $flags) = split(/%%/, shift);
    my @flags_array = split(/,/, $flags);
    return ($str, $context, $hint, \@flags_array); # this will ensure we return exactly 4 values
}

1;