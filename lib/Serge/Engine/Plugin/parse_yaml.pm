package Serge::Engine::Plugin::parse_yaml;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

use File::Path;
use Encode qw(decode_utf8 encode_utf8);
use Serge::Mail;
use Serge::Util qw(xml_escape_strref);
use YAML::XS;

# load boolean values as JSON::PP::Boolean objects
# so that they can be skipped at translation time
# and exported back as booleans
$YAML::XS::Boolean = "JSON::PP";

sub name {
    return 'Generic YAML tree parser plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{errors} = {};

    $self->merge_schema({
        expand_aliases => 'BOOLEAN',

        email_from     => 'STRING',
        email_to       => 'ARRAY',
        email_subject  => 'STRING',

        yaml_kind      => 'STRING',
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

    my $yaml_kind = $self->{data}->{yaml_kind};
    if (defined($yaml_kind) && $yaml_kind !~ /^(rails|generic)$/) {
        print "WARNING: 'yaml_kind' is '$yaml_kind'. Supported values: rails, generic.\n";
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

    my $email_subject = $self->{data}->{email_subject} || ("[".$self->{parent}->{id}.']: YAML Parse Errors');

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

    # Make a copy of the string as we will change it

    my $text = $$textref;

    if (!$self->{data}->{expand_aliases}) {
        # if we don't expand aliases, then we must preserve
        # named anchors (foo: &fooname) and references (bar: *fooname);
        # since parsing will remove anchor names, encode them as a part of the key itself
        $text =~ s/^(\s*\S+)(:\s+)\&(\S+)/$1.'__PRESERVE_ANCHOR__'.$3.$2/mge;
        $text =~ s/^(\s*\S+:\s+)\*/$1.'__PRESERVE_REFERENCE__'/mge;
    }

    # Parse YAML

    my $tree;
    eval {
        ($tree) = Load(encode_utf8($text));
    };
    if ($@) {
        my $error_text = $@;
        $error_text =~ s/\t/ /g;
        $error_text =~ s/^\s+//s;

        $self->{errors}->{$self->{parent}->{engine}->{current_file_rel}} = $error_text;

        die $error_text;
    }

    my $is_rails = $self->{data}->{yaml_kind} eq 'rails';

    if ($is_rails) {
        if (ref($tree) ne 'HASH') {
            my $error_text = "Rails YAML file should start with a root object; something else found";

            $self->{errors}->{$self->{parent}->{engine}->{current_file_rel}} = $error_text;

            die $error_text;
        }

        my @tree_keys = keys %$tree;
        my $tree_count = @tree_keys;
        if ($tree_count == 0) {
            # Special case NOOP. Empty data
        } elsif ($tree_count == 1) {
            $tree = $tree->{$tree_keys[0]};
        } else {
            my $error_text = join(', ', sort @tree_keys);
            $error_text = "YAML file is processed in `rails` mode but has multiple root keys: $error_text";

            $self->{errors}->{$self->{parent}->{engine}->{current_file_rel}} = $error_text;

            die $error_text;
        }
    }

    # Process tree recursively

    $self->process_node('', $tree, $callbackref, $lang);

    # Reconstruct YAML
    if ($lang && $is_rails) {
        my $olr = $self->{parent}->{output_lang_rewrite};
        my $root = defined $olr && exists($olr->{$lang}) ? $olr->{$lang} : $lang;

        $tree = {$root => $tree};
    }

    my $out = decode_utf8(Dump($tree));

    if (!$self->{data}->{expand_aliases}) {
        $out =~ s/^(\s*\S+)__PRESERVE_ANCHOR__(\S+):/$1.': &'.$2/mge;
        $out =~ s/__PRESERVE_REFERENCE__/\*/g;
    }

    return $lang ? $out : undef;
}

sub process_node {
    my ($self, $path, $subtree, $callbackref, $lang, $parent, $key, $is_array) = @_;

    # skip boolean values
    if (ref $subtree eq 'JSON::PP::Boolean') {
        return;
    }

    if (ref($subtree) eq 'HASH') {
        # hash

        foreach my $key (sort keys %$subtree) {
            $self->process_node($path.'/'.$key, $subtree->{$key}, $callbackref, $lang, $subtree, $key, undef);
        }
    } elsif (ref($subtree) eq 'ARRAY') {
        # array

        my $n = 0;
        foreach my $item (@$subtree) {
            $self->process_node($path.'['.$n.']', $item, $callbackref, $lang, $subtree, $n, 1);
            $n++;
        }
    } else {
        # text node

        my $string = $subtree;

        # trim the string
        $string =~ s/^[\r\n\t ]+//sg;
        $string =~ s/[\r\n\t ]+$//sg;

        # translate only non-empty strings;
        # skip values starting with __PRESERVE_ANCHOR__ or __PRESERVE_REFERENCE__
        if (($string ne '') && ($string !~ '^__PRESERVE_(ANCHOR|REFERENCE)__')) {
            if ($lang) {
                my $translated_string = &$callbackref($string, undef, $path, undef, $lang, $path);
                if ($is_array) {
                    $parent->[$key] = $translated_string;
                } else {
                    $parent->{$key} = $translated_string;
                }
            } else {
                &$callbackref($string, undef, $path, undef, undef, $path);
            }
        }
    }
}

1;
