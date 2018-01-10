package Serge::Engine::Plugin::parse_ts;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

no warnings qw(uninitialized);

use File::Path;
use Serge::Mail;
use Serge::Util qw(full_locale_from_lang xml_escape_strref xml_unescape_strref);
use XML::Twig;

sub name {
    return 'Qt Linguist TS parser plugin';
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

    my $email_subject = $self->{data}->{email_subject} || ("[".$self->{parent}->{id}.']: .TS Parse Errors');

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

    my @units = $tree->findnodes('//message');
    map {
        $self->parse_message($_, $callbackref, $lang);
    } @units;

    # update 'language' attribute on <TS> tag
    if ($lang) {
        $tree->root->set_att('language' => &full_locale_from_lang($lang));
    }
}

sub parse_message {
    my ($self, $node, $callbackref, $lang) = @_;

    my $has_source = $node->has_child('source') && $node->first_child('source')->text ne '';
    my $has_translation = $node->has_child('translation') && $node->first_child('translation')->text ne '';

    # in import mode, try to get translations from <translation> tag
    # and skip units without such tag; also skip nodes with an empty source (for sanity)

    return if ($self->{import_mode} && (!$has_translation || !$has_source));

    my $source = $node->first_child('source')->text;
    my $translation = $node->first_child('translation')->text;
    my $context = $self->get_context($node);
    my $hint = $self->get_hint($node);
    my $key = $context.':'.$node->first_child('source')->text;

    my $text = ($self->{import_mode} && $has_translation) ? $translation : $source;

    my $translation = &$callbackref($text, $context, $hint, undef, $lang, $key);

    if ($lang) {
        my $el = $node->first_child('translation');
        $el->set_text($translation);
        $el->strip_att('type'); # remove type attr (e.g. "unfinished")
    }
}

sub get_context {
    my ($self, $node) = @_;

    my @ctx;

    my $parent = $node->parent;
    if ($parent->tag eq 'context') {
        push @ctx, $parent->first_child('name')->text;
    }

    # according to Qt Linguist TS file format spec,
    # (http://doc.qt.io/qt-5/linguist-ts-file-format.html)
    # <extracomment> is used to hold a comment, and <comment>
    # is used to hold the context (sic!)

    my $comment_node = $node->first_child('comment');
    if ($comment_node) {
        push @ctx, $comment_node->text;
    }

    return length(@ctx) > 0 ? join("\n", @ctx) : '';
}

sub get_hint {
    my ($self, $node) = @_;

    # see the note above on <comment> vs <extracomment>

    my $comment_node = $node->first_child('extracomment');
    if ($comment_node) {
        return $comment_node->text;
    }

    return '';
}

1;
