package Serge::Engine::Plugin::parse_markdown;
use parent Serge::Engine::Plugin::Base::Parser;
use parent Serge::Interface::PluginHost;

use strict;

use File::Path;
use Loctools::Markdown::Builder::MD;
use Loctools::Markdown::Parser;
use Serge::Mail;
use Serge::Util qw(normalize_strref);

sub name {
    return 'Markdown parser plugin';
}

# Reference:
#
# MDX: Markdown + JSX components
#       https://mdxjs.com/getting-started
#
# JSX syntax
#       https://reactjs.org/docs/introducing-jsx.html

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{errors} = {};

    $self->merge_schema({
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

    # Copy over errors from the child parser, if any.
    if ($self->{html_parser} && defined $self->{html_parser}->{errors}) {
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

    my $email_subject = $self->{data}->{email_subject} || ("[".$self->{parent}->{id}.']: Markdown Parse Errors');

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

    my $parser = Loctools::Markdown::Parser->new;
    print "\n\n$$textref\n\n";
    my $tree = $parser->parse($$textref);

    $self->process_tree($tree, $callbackref, $lang);

    return undef unless $lang;

    my $builder = Loctools::Markdown::Builder::MD->new;
    return $builder->build($tree);
}

sub process_tree {
    my ($self, $tree, $callbackref, $lang) = @_;

    foreach my $node (@$tree) {
        # Skip preformatted blocks.
        if ($node->{kind} eq 'pre') {
            next;
        }

        # Skip JSX import/export definitions.
        if ($node->{kind} eq 'p' && $node->{text} =~ m/^(import|export) /s) {
            next;
        }

        if ($node->{kind} =~ m/^(li|blockquote)$/) {
            $self->process_tree($node->{children}, $callbackref, $lang);
            next;
        }

        if ($node->{kind} eq 'html') {
            my $html = $node->{text};
            my $is_jsx = $html =~ m/\{.*\}/;

            if ($is_jsx) {
                _preserve_jsx_includes($node);
                $html = $node->{text};
            }

            # Lazy-load html parser plugin
            # (parse_php_xhtml or the one specified in html_parser config node).
            if (!$self->{html_parser}) {
                if (exists $self->{data}->{html_parser}) {
                    $self->{html_parser} = $self->load_plugin_from_node(
                        'Serge::Engine::Plugin', $self->{data}->{html_parser}
                    );
                } else {
                    # Fallback to loading parse_php_xhtml with default parameters.
                    eval('use Serge::Engine::Plugin::parse_php_xhtml; $self->{html_parser} = Serge::Engine::Plugin::parse_php_xhtml->new($self->{parent});');
                    ($@) && die "Can't load parser plugin 'parse_php_xhtml': $@";
                    print "Loaded HTML parser plugin\n" if $self->{parent}->{debug};
                }
            }
        
            $self->{html_parser}->{current_file_rel} = $self->{parent}->{engine}->{current_file_rel}.":XHTML";

            $html = $self->{html_parser}->parse(\$html, $callbackref, $lang);
            next unless $lang;

            $node->{text} = $html;
            _restore_jsx_includes($node);
            next;
        }

        my $string = $node->{text};
        if ($node->{kind}=~ m/^(h\d+|p)$/) {
            normalize_strref(\$string);
        }
        #my $translated_string = &$callbackref($string, $context, $hint, undef, $lang, $key);
        my $translated_string = &$callbackref($string, undef, undef, undef, $lang, undef);
        if ($lang) {
            $node->{text} = $translated_string;
        }
    }
}

sub _preserve_jsx_includes {
    my ($node) = @_;
    my $p = {};
    $node->{context}->{counter} = 0;
    $node->{context}->{placeholders} = $p;
    $node->{text} =~ s/(\{.*?\})/_replace_with_placeholder($node, $1)/sge;
    delete $node->{context}->{counter};
}

sub _replace_with_placeholder {
    my ($node, $placeholder_text) = @_;
    $node->{context}->{counter}++;
    my $replacement = '"__PLACEHOLDER__'.$node->{context}->{counter}.'__"';
    $node->{context}->{placeholders}->{$replacement} = $placeholder_text;
    return $replacement;
}

sub _restore_jsx_includes {
    my ($node) = @_;
    if ($node->{context} && $node->{context}->{placeholders}) {
        my $p = $node->{context}->{placeholders};
        foreach my $key (keys %$p) {
            $node->{text} =~ s/\Q$key\E/$p->{$key}/;
        }
    }
}

1;