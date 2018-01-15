package Serge::Engine::Plugin::serialize_xliff;
use parent Serge::Engine::Plugin::Base::Serializer;

use strict;

use Unicode::Normalize;

use Serge;
use Serge::Util;
use Serge::Util qw(xml_escape_strref xml_unescape_strref);
use XML::Twig;
use XML::Tidy;

sub name {
    return '.XLIFF 1.2 Serializer';
}

sub serialize {
    my ($self, $units, $file, $lang) = @_;

    my $locale = locale_from_lang($lang);

    my $root_element = XML::Twig::Elt->new('xliff', {
            'xmlns' => "urn:oasis:names:tc:xliff:document:1.2",
            version => "1.2",
        });

    my $file_element = $root_element->insert_new_elt('file' => {original => $file, 'source-language' => 'en', 'target-language' => $locale, datatype => 'javapropertyresourcebundle'}, '');

    my $body_element = $file_element->insert_new_elt('body');

    my @reversed_units = reverse(@$units);

    foreach my $unit (@reversed_units) {
        my $unit_element = $body_element->insert_new_elt('trans-unit' => {id => $unit->{key}}, '');

        if ($unit->{hint}) {
            my $resname = ($unit->{hint} =~ /\A(.*?)$/ms)[0];

            $unit_element->set_att(resname => $resname)
        }

        $unit_element->insert_new_elt('target' => {'xml:lang' => $locale}, $unit->{target});

        $unit_element->insert_new_elt('source' => {'xml:lang' => 'en'}, $unit->{source});
    }

    my $tidy_obj = XML::Tidy->new('xml' => $root_element->sprint);

    $tidy_obj->tidy('    ');

    return $tidy_obj->toString();
}

sub deserialize {
    my ($self, $textref) = @_;

    my @units;

    my $tree;
    eval {
        $tree = XML::Twig->new()->parse($$textref);
        $tree->set_indent(' ' x 4);
    };
    if ($@) {
        my $error_text = $@;
        $error_text =~ s/\t/ /g;
        $error_text =~ s/^\s+//s;

        die $error_text;
    }

    my $version = $tree->root->att('version');
    ($version =~ m/^(\d+)/) && ($version = $1);

    my $unit_tag;
    if ($version == 1) {
        $unit_tag = 'trans-unit';
    } elsif ($version == 2) {
        $unit_tag = 'unit';
    } else {
        die "Unsupported XLIFF version: '$version'";
    }

    my @tran_units = $tree->findnodes('//'.$unit_tag);
    foreach my $tran_unit (@tran_units) {
        push @units, {
                key => $tran_unit->att('id'),
                source => $tran_unit->first_child('source')->text,
                context => '',
                target => $tran_unit->first_child('target')->text,
                comment => $tran_unit->att('resname'),
                fuzzy => 0,
                flags => \(),
            };
    }

    return \@units;
}


1;