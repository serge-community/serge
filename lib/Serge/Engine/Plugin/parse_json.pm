package Serge::Engine::Plugin::parse_json;
use parent Serge::Engine::Plugin::Base::Parser;
use parent Serge::Interface::PluginHost;

use strict;

use File::Path;
use JSON::Streaming::Reader;
use JSON -support_by_pp; # -support_by_pp is used to make Perl on Mac happy
use Tie::IxHash;
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
        jsonp             => 'BOOLEAN',
        streaming_mode    => 'BOOLEAN',

        email_from        => 'STRING',
        email_to          => 'ARRAY',
        email_subject     => 'STRING',

        html_parser       => {
            plugin        => 'STRING',

            data          => {
               '*'        => 'DATA',
            }
        },
    });

    $self->add('after_job', \&report_errors);
}

sub report_errors {
    my ($self, $phase) = @_;

    # copy over errors from the child parser, if any
    if ($self->{html_parser}) {
        my @keys = keys %{$self->{html_parser}->{errors}};
        if (scalar @keys > 0) {
            map {
                $self->{errors}->{$_} = $self->{html_parser}->{errors}->{$_};
            } @keys;
            $self->{html_parser}->{errors} = {};
        }
    }

    return if !scalar keys %{$self->{errors}};

    my $email_from = $self->{data}->{email_from};
    my $email_to = $self->{data}->{email_to};

    if (!$email_from || !$email_to) {
        my @a;
        push @a, "'email_from'" unless $email_from;
        push @a, "'email_to'" unless $email_to;
        my $fields = join(' and ', @a);
        my $are = scalar @a > 1 ? 'are' : 'is';
        print "WARNING: there are some parsing errors, but $fields $are not defined, so can't send an email.\n";
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

sub parse_json_as_stream {
    my ($self, $textref) = @_;

    my $jsonr = JSON::Streaming::Reader->for_string($textref);
    my $node = {};
    tie(%$node, 'Tie::IxHash');
    my $root = $node;
    my $prop;
    my $error;
    my @stack = ();

    sub _add_value {
        my ($value, $node, $prop) = @_;
        $prop = $prop.'';

        if (ref $node eq 'HASH') {
            $node->{$prop} = $value;
            return;
        }
        if (ref $node eq 'ARRAY') {
            push @$node, $value;
            return;
        }
        die "Unhandled parent node type ".(ref $node);
    }

    $jsonr->process_tokens(
        start_object => sub {
            push @stack, [$node, $prop]; # save context
            $node = {};
            tie(%$node, 'Tie::IxHash');
        },

        start_property => sub {
            my ($name) = @_;
            $prop = $name;
        },

        end_property => sub {
            $prop = undef;
        },

        end_object => sub {
            my $value = $node;
            ($node, $prop) = @{pop @stack}; # restore context
            _add_value($value, $node, $prop);
        },

        start_array => sub {
            push @stack, [$node, $prop]; # save context
            $node = [];
        },

        end_array => sub {
            my $value = $node;
            ($node, $prop) = @{pop @stack}; # restore context
            _add_value($value, $node, $prop);
        },

        add_string => sub {
            _add_value(shift, $node, $prop);
        },

        add_number => sub {
            _add_value(shift, $node, $prop);
        },

        add_boolean => sub {
            _add_value(shift ? JSON::true : JSON::false, $node, $prop);
        },

        add_null => sub {
            _add_value(JSON::null, $node, $prop);
        },

        error => sub {
            ($error) = @_;
        },
    );

    if (defined $error) {
        return (undef, $error);
    }

    return $root->{''};
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    # Make a copy of the string as we will change it

    my $text = $$textref;
    my $jsonp_prefix = '';
    my $jsonp_suffix = '';

    if ($self->{data}->{jsonp} && $text =~ m/^(.*?)(\{.*\})(.*?)$/s) {
        $jsonp_prefix = $1;
        $text = $2;
        $jsonp_suffix = $3;
    }

    # Parse JSON

    my ($tree, $error_text);
    if ($self->{data}->{streaming_mode}) {
        ($tree, $error_text) = $self->parse_json_as_stream(\$text);
    } else {
        eval {
            ($tree) = from_json($text, {relaxed => 1});
        };
        if ($@ || !$tree) {
            $error_text = $@;
        }
    }

    if (!$tree) {
        if ($error_text) {
            $error_text =~ s/\t/ /g;
            $error_text =~ s/^\s+//s;
        } else {
            $error_text = "parser returned an empty data structure";
        }

        $self->{errors}->{$self->{parent}->{engine}->{current_file_rel}} = $error_text;

        die $error_text;
    }

    # Process tree recursively

    $self->process_node('', $tree, $callbackref, $lang);

    return undef unless $lang; # if in source parsing mode, return nothing

    # Reconstruct JSON

    # need to force indent_length, otherwise it will be zero when PP extension 'escape_slash' is used
    # (looks like an issue in some newer version of JSON:PP)
    # also, when not in the streaming mode, force 'canonical' option to sort keys alphabetically
    # to ensure the structure won't be changed on subsequent script runs
    my $json = to_json($tree, {
        pretty => 1,
        indent_length => 3,
        canonical => !$self->{data}->{streaming_mode},
        escape_slash => 1
    });

    if ($self->{data}->{jsonp}) {
        chomp $json;
        return $jsonp_prefix.$json.$jsonp_suffix;
    }
    return $json;
}

sub process_node {
    my ($self, $path, $subtree, $callbackref, $lang, $parent, $key, $index) = @_;

    if (ref($subtree) eq 'HASH') {
        # hash

        my @keys = $self->{data}->{streaming_mode} ? keys %$subtree : sort keys %$subtree;
        foreach my $key (@keys) {
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
        # restore boolean scalars

        if (JSON::is_bool($subtree)) {
            my $val = $subtree ? JSON::true : JSON::false;
            if (defined $index) {
                $parent->[$index] = $val;
            } else {
                $parent->{$key} = $val;
            }
            return;
        }

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

            # lazy-load html parser plugin
            # (parse_php_xhtml or the one specified in html_parser config node)
            if (!$self->{html_parser}) {
                if (exists $self->{data}->{html_parser}) {
                    # if there's a `html_parser` config node, use it to initialize the plugin
                    $self->{html_parser} = $self->load_plugin_from_node(
                        'Serge::Engine::Plugin', $self->{data}->{html_parser}
                    );
                } else {
                    # otherwise, fall back to loading parse_php_xhtml plugin with default parameters
                    $self->{html_parser} = $self->load_plugin(
                        'Serge::Engine::Plugin::parse_php_xhtml', {}
                    );
                }
            }

            $self->{html_parser}->{current_file_rel} = $self->{parent}->{engine}->{current_file_rel}.":$path";
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