package Serge::Engine::Plugin::Transform::wrappertag;
use parent Serge::Engine::Plugin::Base::Transform;

use strict;

sub name {
    return 'Wrapper tag plugin';
}

sub filter_key {
    my ($self, $s) = @_;
    $s =~ s/^\s*<(\w+).*?>(.+)<\/\1>\s*$/$2/; # remove a single wrapper tag and surrounding whitespace
    return $s;
}

sub transform {
    my ($self, $s, $target) = @_;

    my ($s_start_tag, $s_content, $s_end_tag, $target_start_tag, $target_content, $target_end_tag);

    if ($s =~ m/^(<(\w+).*?>)(.+)(<\/\2>)$/) {
        $s_start_tag = $1;
        $s_content = $3;
        $s_end_tag = $4;
    }

    if ($target =~ m/^(<(\w+).*?>)(.+)(<\/\2>)$/) {
        $target_start_tag = $1;
        $target_content = $3;
        $target_end_tag = $4;
    }

    if (($s_start_tag ne '') && ($s_end_tag ne '') && ($target_start_tag eq '') && ($target_end_tag eq '')) {
        return $s_content;
    }

    if (($s_start_tag eq '') && ($s_end_tag eq '') && ($target_start_tag ne '') && ($target_end_tag ne '')) {
        return $target_start_tag.$s.$target_end_tag;
    }

    return $s;
}

1;