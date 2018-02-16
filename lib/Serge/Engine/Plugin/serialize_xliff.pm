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

    my $file_element = $root_element->insert_new_elt('file' => {original => $file, 'source-language' => 'en', 'target-language' => $locale, datatype => 'x-unknown'}, '');

    my $body_element = $file_element->insert_new_elt('body');

    my @reversed_units = reverse(@$units);

    foreach my $unit (@reversed_units) {
        my $approved = $unit->{fuzzy} ? "no" : "yes";

        my $unit_element = $body_element->insert_new_elt('trans-unit' => {approved => $approved, id => $unit->{key}}, '');

        my $dev_comment = $unit->{hint};

        if ($dev_comment ne '') {
            my @dev_comment_lines = split('\n', $dev_comment);

            my $resname = $dev_comment_lines[0];

            $unit_element->set_att('resname' => $resname);

            my $dev_comment_lines_size = scalar @dev_comment_lines;

            if ($dev_comment_lines_size > 1) {
                shift(@dev_comment_lines);
            } else {
                @dev_comment_lines = \();
            }

            foreach my $dev_comment_line (reverse(@dev_comment_lines)) {
                $unit_element->insert_new_elt('note' => {'from' => 'developer'}, $dev_comment_line);
            }
        }

        if ($unit->{context} ne '') {
            $unit_element->set_att('extradata' => $unit->{context});
        }

        my $target_element = $unit_element->insert_new_elt('target' => {'xml:lang' => $locale}, $unit->{target});

        my $state = '';

        if ($unit->{target} ne '') {
            $state = $self->get_state($unit->{flags});
        } else {
            $state = 'new';
        }

        if ($state ne '') {
            $target_element->set_att('state' => $state);
        }

        $unit_element->insert_new_elt('source' => {'xml:lang' => 'en'}, $unit->{source});
    }

    my $tidy_obj = XML::Tidy->new('xml' => $root_element->sprint);

    $tidy_obj->tidy('    ');

    return $tidy_obj->toString();
}

sub get_state {
    my ($self, $unitflags) = @_;

    return 'translated' unless defined $unitflags;

    my @flags = @$unitflags;

    my $state = 'translated';

    if (is_flag_set(\@flags, 'state-final')) {
        $state = 'final';
    } elsif (is_flag_set(\@flags, 'state-new')) {
        $state = 'new';
    } elsif (is_flag_set(\@flags, 'state-translated')) {
        $state = 'translated';
    } elsif (is_flag_set(\@flags, 'state-signed-off')) {
        $state = 'signed-off';
    } elsif (is_flag_set(\@flags, 'state-needs-translation')) {
        $state = 'needs-translation';
    } else {
    }

    return $state;
}

sub deserialize {
    my ($self, $textref) = @_;

    my @valid_states = split(' ', 'translated final signed-off');

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

    die "Unsupported XLIFF version: '$version'" unless $version eq 1;

    my @tran_units = $tree->findnodes('//trans-unit');
    foreach my $tran_unit (@tran_units) {
        my $comment = '';

        if ($tran_unit->att('resname') ne '') {
            $comment = $tran_unit->att('resname');
            $comment .= '\n';
        }

        $comment .= $self->get_comment($tran_unit);

        my $target_element = $tran_unit->first_child('target');

        my @flags = \();
        my $state = $target_element->att('state');

        if ($state ne '') {
            push @flags, 'state-'.$state;
        }

        my $key = $tran_unit->att('id');

        my $source = $tran_unit->first_child('source')->text;
        my $target = $target_element->text;
        my $context = $tran_unit->att('extradata');
        my $fuzzy = $tran_unit->att('approved') eq "no";

        next unless ($target or $comment);

        if ($state ne '' and @valid_states) {
            my $is_valid_state = $state ~~ @valid_states;

            if (not $is_valid_state) {
                print "\t\t? [invalid state] for $key for with state $state\n";
                next;
            }
        }

        if ($key ne generate_key($source, $context)) {
            print "\t\t? [bad key] $key for context $context\n";
            next;
        }

        push @units, {
                key => $key,
                source => $source,
                context => $context,
                target => $target,
                comment => $comment,
                fuzzy => $fuzzy,
                flags => @flags,
            };
    }

    return \@units;
}

sub get_comment {
    my ($self, $node) = @_;

    my $first_note_node = $node->first_child('note');

    my @notes;

    if (defined $first_note_node) {
        map {
            push @notes, $_->text;
        } $node->children('note');
    }
    return join('\n', @notes);
}


1;