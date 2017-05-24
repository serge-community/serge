package Serge::Engine::Plugin::parse_json;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

use File::Path;
use JSON -support_by_pp; # -support_by_pp is used to make Perl on Mac happy
use Serge::Mail;
use Serge::Util qw(xml_escape_strref);

sub name {
    return 'Generic JSON tree parser plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{errors} = {};

    $self->merge_schema({
        path_matches      => 'ARRAY',
        path_doesnt_match => 'ARRAY',
        path_html         => 'ARRAY',

        email_from        => 'STRING',
        email_to          => 'ARRAY',
        email_subject     => 'STRING',
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

    my $email_subject = $self->{data}->{email_subject} || ("[".$self->{parent}->{id}.']: JSON Parse Errors');

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

    # Parse JSON

    my $tree;
    eval {
        ($tree) = from_json($text, {relaxed => 1});
    };
    if ($@ || !$tree) {
        my $error_text = $@;
        if ($error_text) {
            $error_text =~ s/\t/ /g;
            $error_text =~ s/^\s+//s;
        } else {
            $error_text = "from_json() returned empty data structure";
        }

        $self->{errors}->{$self->{parent}->{engine}->{current_file_rel}} = $error_text;

        die $error_text;
    }

    # Process tree recursively

    $self->process_node('', $tree, $callbackref, $lang);

    # Reconstruct JSON

    # need to force indent_length, otherwise it will be zero when PP extension 'escape_slash' is used
    # (looks like an issue in some newer version of JSON:PP)
    # also, force 'canonical' to sort keys alphabetically to ensure the structure won't be changed on subsequent script runs
    return $lang ? to_json($tree, {pretty => 1, indent_length => 3, canonical => 1, escape_slash => 1}) : undef;
}

sub process_node {
    my ($self, $path, $subtree, $callbackref, $lang, $parent, $key, $index) = @_;

    if (ref($subtree) eq 'HASH') {
        # hash

        foreach my $key (sort keys %$subtree) {
            $self->process_node($path.'/'.$key, $subtree->{$key}, $callbackref, $lang, $subtree, $key);
        }
    } elsif (ref($subtree) eq 'ARRAY') {
        # array

        my $i = 0;
        foreach my $item (@$subtree) {
            # translate only non-empty strings
            $self->process_node($path.'['.$i.']', $item, $callbackref, $lang, $subtree, undef, $i);
            $i++;
        }

    } else {
        # text
        return unless $self->check_path($path);

        print "Text node '$path' matches the rules\n" if $self->{parent}->{debug};

        my $string = $subtree;

        # trim the string
        my $trimmed = $string;
        $trimmed =~ s/^\s+//sg;
        $trimmed =~ s/\s+$//sg;

        # translate only non-empty (and non-whitespace) strings
        if ($trimmed eq '') {
            return;
        }

        if ($self->is_html($path)) {
            # if node is html, pass its text to html parser for string extraction;
            # if html_parser fails to parse the XML due to errors,
            # it will die(), and this will be catched in main application

            # lazy-load PHP/XHTML parser plugin (parse_php_xhtml)
            if (!$self->{html_parser}) {
                eval('use Serge::Engine::Plugin::parse_php_xhtml; $self->{html_parser} = Serge::Engine::Plugin::parse_php_xhtml->new($self->{parent});');
                ($@) && die "Can't load parser plugin 'parse_php_xhtml': $@";
                print "Loaded HTML parser plugin for HTML nodes\n" if $self->{parent}->{debug};
            }

            if ($lang) {
                $string = $self->{html_parser}->parse(\$string, $callbackref, $lang);
            } else {
                $self->{html_parser}->parse(\$string, $callbackref);
                return
            }
        } else {
            # plain-text content
            if ($lang) {
                $string = &$callbackref($string, undef, $path, undef, $lang, $path);
            } else {
                &$callbackref($string, undef, $path, undef, undef, $path);
                return
            }
        }

        if (defined $index) {
            $parent->[$index] = $string;
        } else {
            $parent->{$key} = $string;
        }
    }
}

sub _check_ruleset {
    my ($ruleset, $positive, $value, $default) = @_;

    return $default unless defined $ruleset;

    foreach my $rule (@$ruleset) {
        if ($value =~ m/$rule/s) {
            return $positive;
        }
    }
    return !$positive;
}

sub check_path {
    my ($self, $path) = @_;
    return 0 unless _check_ruleset($self->{data}->{path_matches},          1, $path, 1);
    return 0 unless _check_ruleset($self->{data}->{path_doesnt_match}, undef, $path, 1);
    return 1;
}

sub is_html {
    my ($self, $path) = @_;
    return _check_ruleset($self->{data}->{path_html}, 1, $path, undef);
}

1;