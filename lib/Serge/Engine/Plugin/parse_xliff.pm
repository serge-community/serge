package Serge::Engine::Plugin::parse_xliff;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

no warnings qw(uninitialized);

use File::Path;
use Serge::Mail;
use Serge::Util qw(xml_escape_strref xml_unescape_strref);
use XML::Twig;

sub name {
    return 'XLIFF parser plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{errors} = {};

    $self->merge_schema({
        email_from    => 'STRING',
        email_to      => 'ARRAY',
        email_subject => 'STRING',
    });

    $self->add('after_job', \&report_errors);
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    if (!defined $self->{data}->{email_from}) {
        print "WARNING: 'email_from' is not defined. Will skip sending any reports.\n";
    }

    if (!defined $self->{data}->{email_to}) {
        print "WARNING: 'email_to' is not defined. Will skip sending any reports.\n";
    }
}

sub report_errors {
    my ($self, $phase) = @_;

    my $email_from = $self->{data}->{email_from};
    if (!$email_from) {
        $self->{errors} = {};
        return;
    }

    my $email_to = $self->{data}->{email_to};
    if (!$email_to) {
        $self->{errors} = {};
        return;
    }

    my $email_subject = $self->{data}->{email_subject} || ("[".$self->{parent}->{id}.']: XLIFF Parse Errors');

    my $text;
    foreach my $key (sort keys %{$self->{errors}}) {
        my $pre_contents = $self->{errors}->{$key};
        xml_escape_strref(\$pre_contents);
        $text .= "<hr />\n<p><b style='color: red'>$key</b> <pre>".$pre_contents."</pre></p>\n";
    }

    $self->{errors} = {};

    if ($text) {
        $text = qq|
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
</head>
<body style="font-family: sans-serif; font-size: 120%">

<p>
# This is an automatically generated message.

The following parsing errors were found when attempting to localize resource files.
</p>

$text

</body>
</html>
|;

        Serge::Mail::send_html_message(
            $email_from, # from
            $email_to, # to (list)
            $email_subject, # subject
            $text # message body
        );
    }
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $tree;
    eval {
        $tree = XML::Twig->new()->parse($$textref);
        $tree->set_indent(' ' x 4);
    };
    if ($@) {
        my $error_text = $@;
        $error_text =~ s/\t/ /g;
        $error_text =~ s/^\s+//s;

        $self->{errors}->{$self->{parent}->{engine}->{current_file_rel}} = $error_text;

        die $error_text;
    }

    $self->parse_tree($tree, $callbackref, $lang);

    return $lang ? $tree->sprint(pretty_print => 'indented') : undef;
}

sub parse_tree {
    my ($self, $tree, $callbackref, $lang) = @_;

    my $version = $tree->root->att('version');
    ($version =~ m/^(\d+)/) && ($version = $1);

    $self->{xliff_version} = $version;

    my $unit_tag;
    if ($version == 1) {
        $unit_tag = 'trans-unit';
    } elsif ($version == 2) {
        $unit_tag = 'unit';
    } else {
        die "Unsupported XLIFF version: '$version'";
    }

    my @units = $tree->findnodes('//'.$unit_tag);
    foreach my $unit (@units) {
        if ($unit->has_children('segment')) {
            map {
                $self->parse_segment($_, $callbackref, $lang);
            } $unit->children('segment');
        } else {
            $self->parse_segment($unit, $callbackref, $lang);
        }
    }

    # put 'target-language' on all <file> tags
    if ($lang) {
        map {
            $_->set_att('target-language' => $lang);
        } $tree->findnodes('//file');
    }
}

sub parse_segment {
    my ($self, $node, $callbackref, $lang) = @_;

    my $has_target = $node->has_child('target');

    # in import mode, try to get translations from <target> tag
    # and skip units without such tag

    return if ($self->{import_mode} && !$has_target);

    my $source_tag = ($self->{import_mode} && $has_target) ? 'target' : 'source';

    # get as plain text
    #my $source = $node->first_child($source_tag)->text;

    # get as raw XML (unsafe, but can support placeholders)
    my $source = $node->first_child($source_tag)->inner_xml;

    my $hint = $self->get_context($node);
    my $translation = &$callbackref($source, undef, $hint, undef, $lang, $node->att('id'));

    if ($lang) {
        if ($has_target) {
            # insert as plain text
            #xml_escape_strref(\$translation);

            # add raw XML (unsafe, but can support placeholders)
            $node->first_child('target')->set_inner_xml($translation);
        } else {
            # insert as plain text
            #$node->insert_new_elt('last_child', 'target' => $translation) if $lang;

            # insert as raw XML (unsafe, but can support placeholders)
            $node->insert_new_elt('last_child', 'target')->set_inner_xml($translation);
        }
    }
}

sub get_context {
    my ($self, $node) = @_;

    my @ctx_tags;
    my @ctx_para;

    while ($node) {
        if ($node->tag =~ m/^(trans-unit|unit)$/) {
            unshift @ctx_para, $self->get_notes("Unit note: ", $node);
            unshift @ctx_tags, "unit-id:".$node->att('id') if $node->att('id') ne '';
        }

        if ($node->tag eq 'group') {
            unshift @ctx_para, $self->get_notes("Group note: ", $node);
            unshift @ctx_tags, "group-id:".$node->att('id') if $node->att('id') ne '';
        }

        if ($node->tag eq 'file') {
            unshift @ctx_para, $self->get_notes("File note: ", $self->{xliff_version} == 1 ? $node->first_child('header') : $node);
            unshift @ctx_tags, "file-original:".$node->att('original') if $node->att('original') ne '';
            last;
        }
        $node = $node->parent;
    }

    unshift @ctx_para, join(" ", @ctx_tags);

    return join("\n\n", @ctx_para);
}

sub get_notes {
    my ($self, $prefix, $node) = @_;

    $node = $node->first_child('notes') if defined $node && ($self->{xliff_version} == 2);

    my @notes;

    if (defined $node) {
        map {
            push @notes, $prefix.$_->text;
        } $node->children('note');
    }
    return @notes;
}

1;
