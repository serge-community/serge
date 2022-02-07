package uri;
use parent Serge::Plugin::Base::Callback;

use strict;

use URI::Escape;

sub name {
    return 'Plugin that exposes utility URI functions';
}

sub escape {
    my $s = shift;
    return uri_escape($s);
}

1;