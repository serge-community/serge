use strict;

use Data::Dumper;
use Encode qw(encode_utf8);
use XML::Twig;

my $INFILE = 'plurals.xml';
my $OUTFILE = '../../../lib/Serge/Util/CLDRPlurals.pm';

print "Loading $INFILE\n";
open IN, $INFILE;
binmode IN, 'utf8';
my $json = join('', <IN>);
close IN;

my $tree = XML::Twig->new()->parsefile($INFILE);

my $revision = ($tree->findnodes('/supplementalData/version'))[0]->att('number');

my $plural_names = {};

my @a = $tree->findnodes('//pluralRules');
foreach my $node (@a) {
    my $languages = $node->att('locales');

    my @names = ();
    foreach my $rule ($node->children('pluralRule')) {
        my $text = $rule->text;
        push @names, $rule->att('count') if $text =~ m/\@integer/;
    }

    map {
        $plural_names->{$_} = \@names;
    } split(/\s+/, $languages);
}

my $out = Data::Dumper->new([$plural_names])->Terse(1)->Deepcopy(1)->Sortkeys(1)->Indent(0)->Dump;

$out = qq{package Serge::Util::CLDRPlurals;

# *** THIS FILE WAS AUTO-GENERATED ***
# See <serge_root>/bin/tools/generate-cldr-plurals-package/README

# $revision

use strict;

our \$PLURAL_FORMS = $out;

1;};

# encode explicitly and not via ':utf8'
# to ensure Unix line endings on any platform

print "Saving $OUTFILE\n";
open OUT, ">$OUTFILE";
binmode OUT;
print OUT encode_utf8($out);
close OUT;