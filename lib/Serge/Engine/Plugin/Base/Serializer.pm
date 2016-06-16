package Serge::Engine::Plugin::Base::Serializer;
use parent Serge::Plugin::Base::Callback;

use strict;

# serialize takes the following parameters:
#     $units -- an array of hashes that store unit data
#     $file  -- relative file name
#     $lang  -- target language
# and produces a serialized representation of translation file;
# each hash item in the array represents a translation unit containing
# a set of recognized fields like 'source', 'target', 'comment', 'fuzzy'
#
# virtual method, implementation must be provided in child classes
sub serialize {
    my ($self, $units, $file, $lang) = @_;
    die "Please define your serialize method";
}

# deserialize takes text representation of a transaltion file
# and returns an array of hashes (see `serialize` method above)
#
# virtual method, implementation must be provided in child classes
sub deserialize {
    my ($self, $textref) = @_;
    die "Please define your deserialize method";
}

1;