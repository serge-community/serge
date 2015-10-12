package Serge::Engine::Plugin::Transform::tags;
use parent Serge::Engine::Plugin::Base::Transform;

use strict;

sub name {
    return 'Tag replacement plugin';
}

sub filter_key {
    my ($self, $s) = @_;

    my $n = 0;

    # support simple cases like "aaa <div><strong>bbb</strong></div> ccc"
    # and tags with processing instructions in them:
    # "aaa <div<? if ($foo): ?> class="foo"<? endif ?>>bbb</div> ccc"

    # test if the string consists of just tags and whitespace,
    # and if this is the case, just return an empty string
    # (which means that the translation can simply be copied from the source)
    my $test = $s;
    $test =~ s/<[^<>]*?((<\?.*?\?>)*[^<>]*?)*>//sg; # remove all tags
    if ($test !~ m/\S/) {
        return '';
    }

    $s =~ s/<[^<>]*?((<\?.*?\?>)*[^<>]*?)*>/'[tag:'.($n++).']'/ge;

    return $s;
}

sub transform {
    my ($self, $s, $target) = @_;

    my ($s_start_tag, $s_content, $s_end_tag, $target_start_tag, $target_content, $target_end_tag);

    my @tags = ();
    my $n = 0;
    while ($target =~ m/(<.*?((<\?.*?\?>)*.*?)*>)/g) {
        push @tags, $1;
    }

    my $n = 0;
    $s =~ s/<.*?((<\?.*?\?>)*.*?)*>/$tags[$n++]/ge;

    return $s;
}

1;