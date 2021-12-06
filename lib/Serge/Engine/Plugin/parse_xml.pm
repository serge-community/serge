package Serge::Engine::Plugin::parse_xml;
use parent Serge::Engine::Plugin::Base::Parser;
use parent Serge::Interface::PluginHost;

use strict;

no warnings qw(uninitialized);

use File::Path;
use Serge::Mail;
use Serge::Util qw(xml_escape_strref xml_unescape_strref);

sub name {
    return 'Generic XML parser plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{errors} = {};

    $self->merge_schema({
        node_match      => 'ARRAY',
        node_exclude    => 'ARRAY',
        node_html       => 'ARRAY',
        comment_attrs   => 'ARRAY',
        autodetect_html => 'BOOLEAN',
        xml_kind        => 'STRING',

        email_from      => 'STRING',
        email_to        => 'ARRAY',
        email_subject   => 'STRING',

        html_parser     => {
            plugin      => 'STRING',

            data        => {
               '*'      => 'DATA',
            }
        },
    });

    $self->add('after_job', \&report_errors);
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    if (exists $self->{data}->{xml_kind} && ($self->{data}->{xml_kind} !~ m/^(generic|android|indesign)$/)) {
        die "Unsupported xml_kind: '$self->{data}->{xml_kind}'. You can use 'generic' (default), 'android' or 'indesign'";
    }

    $self->{data}->{xml_kind_android} = ($self->{data}->{xml_kind} eq 'android');
    $self->{data}->{xml_kind_indesign} = ($self->{data}->{xml_kind} eq 'indesign');
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

    my $email_subject = $self->{data}->{email_subject} || ("[".$self->{parent}->{id}.']: XML Parse Errors');

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

    die 'node_match not specified' unless $self->{data}->{node_match};

    # Make a copy of the string as we will change it

    my $text = $$textref;

    # Replace the symbolic entities as we are not going to expand them

    $text =~ s/&(\w+);/'__HTML__ENTITY__'.$1.'__'/ge;

    # Wrap CDATA blocks inside special '__CDATA' tag
    # to be able to reconstruct it later

    $text =~ s/(<\!\[CDATA\[.*?\]\]>)/'<__CDATA>'._escape_pi_and_comments($1).'<\/__CDATA>'/sge;

    # Wrap processing instruction inside special '__PI' tag
    # to be able to reconstruct it later

    $text =~ s/<\?(.*?)\?>/<__PI><\!\[CDATA\[$1\]\]><\/__PI>/sg;

    # Wrap HTML comment inside special '__COMMENT' tag
    # to be able to reconstruct it later

    $text =~ s/<\!--(.*?)-->/<__COMMENT><\!\[CDATA\[$1\]\]><\/__COMMENT>/sg;

    # Restore escaped processing instructions and comments inside cdata

    $text = _unescape_pi_and_comments($text);

    # Add the dummy root tag for XML to be valid

    $text = '<__ROOT>'.$text.'</__ROOT>';

    # Create XML parser object

    use XML::Parser;
    use XML::Parser::Style::IxTree;
    my $parser = new XML::Parser(Style => 'IxTree');

    # Parse XML

    my $tree;
    eval {
        $tree = $parser->parse($text);
    };
    if ($@) {
        my $error_text = $@;
        $error_text =~ s/\t/ /g;
        $error_text =~ s/^\s+//s;

        $self->{errors}->{$self->{parent}->{engine}->{current_file_rel}} = $error_text;

        die $error_text;
    }

    # Add the empty attributes hash to the root tag (for uniform processing)

    unshift @$tree, {};

    # Process tree recursively and generate the localized output

    my $out = $self->render_tag_recursively('', $tree, $callbackref, $lang, '');

    return $lang ? $out : undef;
}

sub _escape_pi_and_comments {
    my $text = shift;

    $text =~ s/<\?/__PI_START__/sg;
    $text =~ s/\?>/__PI_END__/sg;
    $text =~ s/<\!--/__COMMENT_START__/sg;
    $text =~ s/-->/__COMMENT_END__/sg;

    return $text;
}

sub _unescape_pi_and_comments {
    my $text = shift;

    $text =~ s/__PI_START__/<\?/sg;
    $text =~ s/__PI_END__/\?>/sg;
    $text =~ s/__COMMENT_START__/<\!--/sg;
    $text =~ s/__COMMENT_END__/-->/sg;

    return $text;
}

sub process_text_node {
    my ($self, $path, $attrs, $strref, $callbackref, $lang, $cdata, $noquotes) = @_;

    # Check if node path matches our expectations

    my $ok = undef;

    # Test if node path matches the mask

    foreach my $rule (@{$self->{data}->{node_match}}) {
        if (ref($rule) eq "HASH") {
            my $prule = $rule->{path};
            if ($path =~ m/$prule/) {
                my $attrs_ok = 1;
                foreach my $name (keys %{$rule->{attributes}}) {
                    my $arule = $rule->{attributes}->{$name};
                    if ($attrs->{$name} !~ m/$arule/) {
                        print "\t\t\tattribute '$name' [".$attrs->{$name}."] doesn't match rule '$arule'\n" if $self->{parent}->{debug};
                        $attrs_ok = undef;
                        last;
                    }
                }
                if ($attrs_ok) {
                    $ok = 1;
                    last;
                }
            } else {
                print "\t\t\tpath doesn't match\n" if $self->{parent}->{debug};
            }
        } else { # treat rule as a string
            if ($path =~ m/$rule/) {
                $ok = 1;
                last;
            }
        }
    }

    # Test if node path does not match the exclusion mask

    if ($ok) {
        foreach my $rule (@{$self->{data}->{node_exclude}}) {
            if (ref($rule) eq "HASH") {
                my $prule = $rule->{path};
                if ($path =~ m/$prule/) {
                    my $attrs_ok = 1;
                    foreach my $name (keys %{$rule->{attributes}}) {
                        my $arule = $rule->{attributes}->{$name};
                        if ($attrs->{$name} !~ m/$arule/) {
                            print "\t\t\t[exclude] attribute '$name' [".$attrs->{$name}."] doesn't match rule '$arule'\n" if $self->{parent}->{debug};
                            $attrs_ok = undef;
                            last;
                        }
                    }
                    if ($attrs_ok) {
                        $ok = undef;
                        last;
                    }
                } else {
                    print "\t\t\t[exclude] path doesn't match\n" if $self->{parent}->{debug};
                }
            } else { # treat rule as a string
                if ($path =~ m/$rule/) {
                    $ok = undef;
                    last;
                }
            }
        }
    }

    # Test if node path matches the html mask

    my $is_html = undef;

    if ($ok) {
        foreach my $rule (@{$self->{data}->{node_html}}) {
            if (ref($rule) eq "HASH") {
                my $prule = $rule->{path};
                if ($path =~ m/$prule/) {
                    my $attrs_ok = 1;
                    foreach my $name (keys %{$rule->{attributes}}) {
                        my $arule = $rule->{attributes}->{$name};
                        if ($attrs->{$name} !~ m/$arule/) {
                            print "\t\t\tattribute '$name' [".$attrs->{$name}."] doesn't match rule '$arule'\n" if $self->{parent}->{debug};
                            $attrs_ok = undef;
                            last;
                        }
                    }
                    if ($attrs_ok) {
                        $is_html = 1;
                        last;
                    }
                } else {
                    print "\t\t\tpath doesn't match\n" if $self->{parent}->{debug};
                }
            } else { # treat rule as a string
                if ($path =~ m/$rule/) {
                    $is_html = 1;
                    last;
                }
            }
        }
    }

    if ($self->{parent}->{debug}) {
        if ($ok) {
            if ($is_html) {
                print "\t\t[ok, HTML mode] $path\n";
            } else {
                print "\t\t[ok] $path\n";
            }
        } else {
            print "\t\t[--] $path\n";
        }
    }

    # reconstruct original XML with symbolic entities
    # (do this before we exit to make sure all text nodes, even those
    # not matching the mask, will be restored)
    $$strref =~ s/__HTML__ENTITY__(\w+?)__/&$1;/g;

    # now exit if the node doesn't match the mask
    return unless $ok;

    # in InDesign mode, strip the line break Unicode symbols since these are generally English-specific
    # (? need to verify ?)
    if ($self->{data}->{xml_kind_indesign}) {
        $$strref =~ s/\x{2028}//g; # Unicode Character 'LINE SEPARATOR' (U+2028)
    }

    # trim the string
    my $trimmed = $$strref;

    $trimmed =~ s/^\s+//sg;
    $trimmed =~ s/\s+$//sg;

    # gather the comment attributes
    my $comment_attrs = $self->{data}->{comment_attrs} || [];

    my @comments = ($path);
    foreach my $name (sort @$comment_attrs) {
        if (exists $attrs->{$name}) {
            push @comments, "$name = $attrs->{$name}";
        }
    }
    my $comment = join("\n\n", @comments);

    # 1) skip empty strings
    # 2) skip strings consisting of non-alphabet characters (bullets, arrows, etc.)
    # 3) skip strings representing plain numbers
    if ($trimmed ne '' && $trimmed !~ m/^(\W+|\d+)$/) {
        # in InDesign mode, preserve the leading and trailing whitespace
        my ($leading_whitespace, $trailing_whitespace);
        if ($self->{data}->{xml_kind_indesign}) {
            ($$strref =~ m/^(\s+)/) && ($leading_whitespace = $1);
            ($$strref =~ m/(\s+)$/) && ($trailing_whitespace = $1);
        }

        $$strref = $trimmed;

        # unescape basic XML entities unless we're inside CDATA block
        xml_unescape_strref($strref) unless $cdata;

        if ($self->{data}->{autodetect_html}) {
            # auto-detect HTML by the opening tag
            $is_html = 1 if $$strref =~ m/^</s;
        }

        if ($is_html) {
            # if node is html, pass its text to html parser for string extraction
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

            my $nested_html_callbackref = sub {
                my ($string, $context, $hint, $flagsref, $lang, $key) = @_;
                &$callbackref($string, $context, $hint, $flagsref, $lang, $path.$key);
            };

            $self->{html_parser}->{current_file_rel} = $self->{parent}->{engine}->{current_file_rel}.":$path";
            if ($lang) {
                $$strref = $self->{html_parser}->parse($strref, $nested_html_callbackref, $lang);
                if (defined $$strref) {
                    # escape unsafe xml chars unless we're in CDATA block
                    xml_escape_strref($strref, $noquotes) unless $cdata;
                } else {
                    $$strref = $trimmed;
                }
            } else {
                $self->{html_parser}->parse($strref, $nested_html_callbackref);
            }
        } else {
            # additionally unescape Android-specific stuff, if requested
            _android_unescape($strref) if ($self->{data}->{xml_kind_android});

            if ($lang) {
                $$strref = &$callbackref($$strref, undef, $comment, undef, $lang, $path);
            } else {
                &$callbackref($$strref, undef, $comment, undef, undef, $path);
            }

            # escape Android-specific stuff if requested
            _android_escape($strref) if ($self->{data}->{xml_kind_android});

            # preserve symbolic entities from escaping
            $$strref =~ s/&(\w+);/'__HTML__ENTITY__'.$1.'__'/ge;

            # escape unsafe xml chars (in Android mode, do not xml-escape quotes)
            $noquotes = $noquotes || $self->{data}->{xml_kind_android};
            xml_escape_strref($strref, $noquotes) unless $cdata;

            # restore symbolic entities
            $$strref =~ s/__HTML__ENTITY__(\w+?)__/&$1;/g;

            # in InDesign mode, make sure the leading and trailing whitespace
            # is restored to the original values
            if ($self->{data}->{xml_kind_indesign}) {
                $$strref =~ s/^(\s+)/$leading_whitespace/e;
                $$strref =~ s/(\s+)$/$trailing_whitespace/e;
            }
        }
    }
}

sub _android_unescape {
    my ($strref) = @_;

    $$strref =~ s/\\'/'/g; # Android-specific apostrophe unescaping
    $$strref =~ s/\\"/"/g; # Android-specific quote unescaping
}

sub _android_escape {
    my ($strref) = @_;

    $$strref =~ s/'/\\'/g; # Android-specific apostrophe escaping
    $$strref =~ s/"/\\"/g; # Android-specific quote escaping

}

sub _dummy_callback {
    my ($s) = @_;
    return $s;
}

sub render_tag_recursively {
    my ($self, $name, $subtree, $callbackref, $lang, $path, $cdata, $parent_attrs) = @_;
    my $attrs = $subtree->[0];

    $cdata = 1 if (($name eq '__CDATA') || ($name eq '__COMMENT') || ($name eq '__PI'));

    my $inner_xml = '';

    for (my $i = 0; $i < (scalar(@$subtree) - 1) / 2; $i++) {
        my $tagname = $subtree->[1 + $i*2];
        my $tagtree = $subtree->[1 + $i*2 + 1];

        # do not process text inside processing instructions
        # TODO: this can potentially be a conditional option, disabled by default
        if ($tagname eq '__PI') {
            $inner_xml .= $self->render_tag_recursively($tagname, $tagtree, \&_dummy_callback, $lang, $path, $cdata, $attrs);
            next;
        }

        if ($tagname ne '0') {
            # node does not contain plain text, render the subtree

            my $tagpath;
            if (($tagname eq '__ROOT') || ($tagname eq '__CDATA') || ($tagname eq '__COMMENT') || ($tagname eq '__PI')) {
                $tagpath = $path;
            } else {
                $tagpath = $path.'/'.$tagname;
            }

            if ($lang) {
                $inner_xml .= $self->render_tag_recursively($tagname, $tagtree, $callbackref, $lang, $tagpath, $cdata, $attrs);
            } else {
                $self->render_tag_recursively($tagname, $tagtree, $callbackref, $lang, $tagpath, $cdata, $attrs);
            }
        } else {
            # tagtree holds a string for text nodes

            my $str = $tagtree;

            $self->process_text_node($path, $parent_attrs, \$str, $callbackref, $lang, $cdata, 1);

            if ($lang) {
                $inner_xml .= $str;
            }
        }
    }

    # Generating the string consisting of [ attr="value"] pairs

    my $attrs_text;

    foreach my $key (sort keys %$attrs) {
        my $str = $attrs->{$key};

        my $tagpath = $path.'@'.$key;

        $self->process_text_node($tagpath, $attrs, \$str, $callbackref, $lang, undef, undef);

        if ($lang) {
            $attrs_text .= " $key=\"$str\"";
        }
    }

    # Construct and return the tag string with its inner xml

    if ($lang) {
        if ($name eq '__CDATA') {
            return '<![CDATA['.$inner_xml.']]>';
        }

        if ($name eq '__COMMENT') {
            return '<!--'.$inner_xml.'-->';
        }

        if ($name eq '__PI') {
            return '<?'.$inner_xml.'?>';
        }

        if (($name ne '') && ($name ne '__ROOT')) {
            return "<$name$attrs_text>$inner_xml</$name>";
        }

        return $inner_xml;
    }
}

1;