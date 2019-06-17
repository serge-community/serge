package Serge::Engine::Plugin::Transform::endpunc;
use parent Serge::Engine::Plugin::Base::Transform;

use strict;
use utf8;

sub name {
    return 'End punctuation plugin';
}

sub filter_key {
    my ($self, $s) = @_;
    $s =~ s/[^\w\d\]\)\>]+$//; # remove all trailing non-character symbols
    return $s;
}

sub transform {
    my ($self, $s, $target, $lang) = @_;

    my $sourcepunc = '';
    if ($s =~ m/([^\w\d\]\)\>]+)$/) {
        $sourcepunc = $1;
    }

    my $targetpunc = '';
    if ($target =~ m/([^\w\d\]\)\>]+)$/) {
        $targetpunc = $1;
    }

    if ($sourcepunc eq $targetpunc && $targetpunc eq '') {
        # try to get rid of the trailing tags and whitespace to get the actual punctuation
        my $filtered_target = $target;
        $filtered_target =~ s/\s*<[^<>]+>\s*$//s;
        if ($filtered_target ne $target) {
            return $self->transform($s, $filtered_target, $lang);
        }
    }

    if ($sourcepunc ne $targetpunc) {
        # In Japanese, replace certain punctuation symbols
        if ($lang =~ m/^(ja|ja-.*)$/) {
            $targetpunc = _adjust_japanese_punctuation($targetpunc);
        }

        $s =~ s/[^\w\d\]\)\>]*$/$targetpunc/e;
    }

    return $s;
}

sub _adjust_japanese_punctuation {
    my $s = shift;
    $s =~ s/\.{3}/…/g;
    $s =~ tr/.?!/。？！/;
    return $s;
}

1;