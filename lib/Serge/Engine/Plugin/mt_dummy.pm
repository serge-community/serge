package Serge::Engine::Plugin::mt_dummy;
use parent Serge::Engine::Plugin::Base::MT;

use strict;
use warnings;

sub name {
    return 'Dummy machine translation provider (for testing purposes)';
}

sub mt_get_translation {
    my ($self, $src_lang, $target_lang, $s) = @_;

    return "[mt:$src_lang:$target_lang]".$s.'[/mt]';
}

1;