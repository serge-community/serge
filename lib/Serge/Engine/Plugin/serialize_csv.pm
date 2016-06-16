package Serge::Engine::Plugin::serialize_csv;
use parent Serge::Engine::Plugin::Base::Serializer;

use strict;

use Unicode::Normalize;

use Serge;
use Serge::Util;

my @field_names = qw(key context hint source target fuzzy comment);

sub name {
    return '.CSV Serializer';
}

sub serialize {
    my ($self, $units, $file, $lang) = @_;
    unshift @$units, ({
        key     => 'ID',
        context => 'Context',
        hint    => 'Hint',
        source  => 'Source',
        target  => 'Translation',
        fuzzy   => 'Needs Work',
        comment => "Translator's Comment",
    });
    return make_csv($units, \@field_names);
}

sub deserialize {
    my ($self, $textref) = @_;
    my @units;

    $$textref =~ s/\r\n/\n/sg; # normalize line-feeds

    my @row;
    while ($$textref =~ /([^,"]*?|"(?:[^"]|"")*?")([,\n])/sg) {
        push @row, unescape_csv_value($1);
        if ($2 eq "\n") {
            if ($row[0] ne 'ID') {
                my %h;
                @h{@field_names} = @row;
                $h{fuzzy} = $h{fuzzy} ? 1 : 0;
                push @units, \%h;
            }
            @row = ();
        }
    }
    return \@units;
}

sub make_csv {
    my ($units, $field_names) = @_;
    my $out = '';
    foreach my $unit (@$units) {
        $unit->{fuzzy} = $unit->{fuzzy} ? 1 : undef if ($unit->{key} ne 'ID'); # normalize the value except for the header row
        $out .= join(',', map { escape_csv_value($unit->{$_}) } @$field_names)."\n";
    }
    return $out;
}

sub escape_csv_value {
    my $s = shift;
    if ($s =~ m/(^\s|[",\n]|\s$)/) {
        $s =~ s/"/""/g;
        return qq{"$s"};
    }
    return $s;
}

sub unescape_csv_value {
    my $s = shift;
    if ($s =~ m/^".*"$/s) {
        $s =~ s/^"(.*)"$/$1/se;
        $s =~ s/""/"/g;
    }
    $s = undef if $s eq '';
    return $s;
}

1;