package Serge::Engine::Plugin::serialize_xliff;
use parent Serge::Engine::Plugin::Base::Serializer;

use strict;

use Serge;
use Serge::Util;
use XML::Twig;

sub name {
    return '.XLIFF 1.2 Serializer';
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    eval('use XML::Tidy;');
    die "ERROR: To use serialize_xliff parser, please install XML::Tidy module (run 'cpan XML::Tidy')\n" if $@;
}

sub serialize {
    my ($self, $units, $file, $lang) = @_;

    my $engine= $self->{parent}->{engine};

    my $file_id = $engine->{current_file_id};

    my $db = $engine->{db};

    my $source_lang = $self->{parent}->{source_language};

    my $source_locale = $self->language_from_lang($source_lang);
    my $target_locale = $self->language_from_lang($lang);

    my $root_element = XML::Twig::Elt->new('xliff', {
        'xmlns' => "urn:oasis:names:tc:xliff:document:1.2",
        version => "1.2",
    });

    my $file_element = $root_element->insert_new_elt('file' => {original => $file, 'source-language' => $source_locale, datatype => 'x-unknown'}, '');

    if ($source_lang ne $lang) {
        $file_element->set_att('target-language' => $target_locale);
    }

    my $body_element = $file_element->insert_new_elt('body');

    my @reversed_units = reverse(@$units);

    foreach my $unit (@reversed_units) {
        my $unit_element = $body_element->insert_new_elt('trans-unit' => {}, '');

        $unit_element->set_att('xml:space' => 'preserve');

        if ($source_lang ne $lang && $unit->{target} ne '') {
            my $approved = $unit->{fuzzy} ? "no" : "yes";

            $unit_element->set_att(approved => $approved);
        }

        my $serge_context_group_element = $unit_element->insert_new_elt('context-group' => {name => 'serge', purpose => 'x-serge'}, '');

        if ($unit->{context} ne '') {
            $serge_context_group_element->insert_new_elt('context' => { 'context-type' => 'x-serge-context' }, $unit->{context});
        }

        $serge_context_group_element->insert_new_elt('context' => { 'context-type' => 'x-serge-file-id' }, $file_id);

        my $string_id = $db->get_string_id($unit->{source}, $unit->{context}, 1); # do not create the string, just look if there is one

        # get item_id for current namespace/file and string/context

        my $item_id = $db->get_item_id($file_id, $string_id, undef, 1); # do not create

        if ($item_id) {
            $serge_context_group_element->insert_new_elt('context' => { 'context-type' => 'x-serge-id' }, $item_id);
        }

        my $key = $unit->{key};
        my $dev_comment = $unit->{hint};
        my $resname = '';

        if ($dev_comment ne '') {
            my @dev_comment_lines = split('\n', $dev_comment);

            foreach my $dev_comment_line (reverse(@dev_comment_lines)) {
                $unit_element->insert_new_elt('note' => {'from' => 'developer'}, $dev_comment_line);
            }
        }

        $unit_element->set_att('id' => $key);

        if ($resname ne '') {
            $unit_element->set_att('resname' => $resname);
        }

        my $target_element = $unit_element->insert_new_elt('target' => {'xml:lang' => $target_locale}, $unit->{target});

        my $state = '';

        if ($unit->{target} ne '') {
            $state = 'translated';
        } else {
            $state = 'new';
        }

        if ($state ne '') {
            $target_element->set_att('state' => $state);
        }

        $unit_element->insert_new_elt('source' => {'xml:lang' => $source_locale}, $unit->{source});
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

    die "Unsupported XLIFF version: '$version'" unless $version eq 1;

    my @tran_units = $tree->findnodes('//trans-unit');
    foreach my $tran_unit (@tran_units) {
        my $key = '';
        my $context = '';
        my $comment = '';

        my $tran_unit_id = $tran_unit->att('id');

        $key = $tran_unit_id;

        my $context_group_element = $tran_unit->first_child("context-group[\@purpose='x-serge']");

        if (defined $context_group_element) {
            my @context_units = $context_group_element->findnodes("context[\@context-type='x-serge-context']");

            if (@context_units) {
                $context = $context_units[0]->text;
            }
        }

        my @translator_note_units = $tran_unit->findnodes("note[\@from='translator']");

        if (@translator_note_units) {
            my @translator_notes = map { $_->text } @translator_note_units;

            $comment = join('\n', @translator_notes);
        }

        my $source_element = $tran_unit->first_child('source');
        my $target_element = $tran_unit->first_child('target');

        my @flags = \();
        my $target = '';

        if ($target_element) {
            $target = $target_element->text;
        } else {
            print "\t\t? [missing target] for $key\n";
        }

        my $source = '';

        if ($source_element) {
            $source = $source_element->text;
        }

        my $fuzzy = 0;

        $fuzzy = $tran_unit->att('approved') eq "no";

        if ($key eq '') {
            print "\t\t? [empty key]\n";
            next;
        }

        if ($key ne generate_key($source, $context)) {
            print "\t\t? [bad key] $key for context $context\n";
            next;
        }

        next unless ($target or $comment);

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

sub language_from_lang {
    my ($self, $language) = @_;
    $language =~ s/(-.+?)(-.+)?$/uc($1).$2/e; # convert e.g. 'pt-br-Whatever' to 'pt-BR-Whatever'
    return $language;
}

1;
