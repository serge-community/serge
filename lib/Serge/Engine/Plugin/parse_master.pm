package Serge::Engine::Plugin::parse_master;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

no warnings qw(uninitialized);

sub name {
    return 'Master files parser plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{errors} = {};

    $self->merge_schema({
        opening_marker => 'STRING',
        closing_marker => 'STRING',
        delimiter => 'STRING',
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    $self->{data}->{opening_marker} = '<%' unless $self->{data}->{opening_marker} ne '';
    $self->{data}->{closing_marker} = '%>' unless $self->{data}->{closing_marker} ne '';
    $self->{data}->{delimiter} = '%%' unless $self->{data}->{delimiter} ne '';
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

    my $o = $self->{data}->{opening_marker};
    my $c = $self->{data}->{closing_marker};

    if ($lang) {
        # do a substitution (on a copy of the string)
        my $translated_text = $$textref;
        $translated_text =~ s|$o(.*?)$c|&$callbackref($self->_split_params($1), $lang)|sge;
        return $translated_text;
    } else {
        # just match strings (faster)
        while ($$textref =~ m/$o(.*?)$c/sg) { &$callbackref($self->_split_params($1), undef); }
        return undef;
    }
}

sub _split_params {
    my ($self, $text) = @_;
    my $d = $self->{data}->{delimiter};
    my ($str, $context, $hint, $flags) = split(/$d/, $text);
    my @flags_array = split(/,/, $flags);
    return ($str, $context, $hint, \@flags_array); # this will ensure we return exactly 4 values
}

1;