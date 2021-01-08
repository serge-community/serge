package Serge::Engine::Plugin::parse_php_xhtml;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

no warnings qw(uninitialized);

use HTML::Entities;
use Serge::Mail;
use Serge::Util qw(locale_from_lang xml_escape_strref);

sub name {
    return 'PHP/XHTML static content parser plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{extractable_tags} = {};
    $self->{errors} = {};
    $self->{php_blocks} = [];

    $self->merge_schema({
        expand_entities => 'BOOLEAN',
        validate_output => 'BOOLEAN',

        include_tags    => 'ARRAY',
        exclude_tags    => 'ARRAY',

        email_from      => 'STRING',
        email_to        => 'ARRAY',
        email_subject   => 'STRING',
    });

    $self->add('can_save_localized_file', \&validate_output);
    $self->add('after_job', \&report_errors);

    # initialize the default list of tags that are used for content extraction
    map {
        $self->{extractable_tags}->{$_} = 1;
    } qw(h1 h2 h3 h4 h5 h6 h7 p li dt dd label option);

    # bare HTML (content of the root node) is also considered translated by default
    # (provided there are no inner tags that override the segmentation);
    # such content is identified by an empty tag name
    $self->{extractable_tags}->{''} = 1;

    # apply the list of tags from `include_tags`
    if (defined $self->{data}->{include_tags}) {
        map {
            $self->{extractable_tags}->{$_} = 1;
        } @{$self->{data}->{include_tags}};
    }

    # remove tags listed in `exclude_tags`
    if (defined $self->{data}->{exclude_tags}) {
        map {
            delete $self->{extractable_tags}->{$_};
        } @{$self->{data}->{exclude_tags}};
    }
}

sub validate_output {
    my ($self, $phase, $file, $lang, $textref) = @_;

    # return values:
    #   0 - prohibit saving the file
    #   1 - allow saving the file

    return 1 unless $self->{data}->{validate_output};

    $self->{current_file_rel} = "$file:$lang";
    eval {
        $self->parse($textref, sub {});
    };
    delete $self->{current_file_rel};
    return $@ ? 0 : 1;
}

sub report_errors {
    my ($self, $phase) = @_;

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

    my $email_subject = $self->{data}->{email_subject} || ("[".$self->{parent}->{id}.']: PHP/XHTML Parse Errors');

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
        print 'Errors found. Sending error report to '.join(', ', @$email_to)."\n";

        Serge::Mail::send_html_message(
            $email_from, # from
            $email_to, # to (list)
            $email_subject, # subject
            $text # message body
        );
    }

}

sub add_php_block {
    my ($self, $text) = @_;
    push @{$self->{php_blocks}}, $text;
    return scalar(@{$self->{php_blocks}});
}

sub reconstruct_xml {
    my ($self, $strref) = @_;

    # Substituting PHP blocks

    for (my $i = 1; $i <= scalar(@{$self->{php_blocks}}); $i++) {
        my $block = $self->{php_blocks}->[$i - 1];
        $$strref =~ s/__PHP__BLOCK__($i)__/<\?$block\?>/;
    }

    # Substituting symbolic entities

    $$strref =~ s/__HTML__ENTITY__(\w+?)__/&$1;/g;

    # Recreating DOCTYPE declaration

    $$strref =~ s/__DOCTYPE__(.*?)__END_DOCTYPE__/<!DOCTYPE$1>/sg;

}

sub get_current_file_rel {
    my ($self) = @_;
    return $self->{current_file_rel} || $self->{parent}->{engine}->{current_file_rel};
}

sub die_with_error {
    my ($self, $error, $textref) = @_;
    my $start_pos = $-[0];
    my $end_pos = $+[0];
    my $around = 40;
    my $s = substr($$textref, $start_pos-$around, $end_pos - $start_pos + $around * 2);
    $s =~ s/\n/ /sg;
    my $message = $error.":\n".
        "$s\n".
        ('-' x $around)."^\n";

    $self->{errors}->{$self->get_current_file_rel} = $message;
    die $message;
}

my $in_cdata;
my $in_tag;
my $in_attr;
sub fix_php_blocks {
    my ($self, $s, $textref) = @_;

    #print $-[0].':'.$+[0]."\n";

    if ($s eq '<![CDATA[') {
        if ($in_cdata) {
            my $error = "Premature '<![CDATA['";
            $self->die_with_error($error, $textref);
        } else {
            $in_cdata = 1;
        }
    } elsif ($s eq ']]>') {
        if (!$in_cdata) {
            my $error = "Premature ']]>'";
            $self->die_with_error($error, $textref);
        } else {
            $in_cdata = undef;
        }
    } elsif ($s eq '<') {
        if (!$in_cdata) {
            if ($in_tag) {
                my $error = "Premature '<'";
                $self->die_with_error($error, $textref);
            } else {
                $in_tag = 1;
            }
        }
    } elsif ($s eq '>') {
        if (!$in_cdata) {
            if (!$in_tag) {
                my $error = "Premature '>'";
                $self->die_with_error($error, $textref);
            } elsif ($in_attr) {
                my $error = "Premature '>' before '\"'";
                $self->die_with_error($error, $textref);
            } else {
                $in_tag = undef;
            }
        }
    } elsif ($s eq '"') {
        if (!$in_cdata && $in_tag) {
            $in_attr = !$in_attr;
        }
    } else { # PHP block
        if (!$in_cdata && $in_tag && !$in_attr) {
            $s = " $s=\"\" ";
        }
    }

    return $s;
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    # Making a copy of the string as we will change it

    my $text = $$textref;

    # Clearing the php_blocks array

    $self->{php_blocks} = [];

    # Replacing the '<?' and '?>' with different markers to make XML valid,
    # and wrapping the PHP code into CDATA block

    $text =~ s/<\?(.*?)\?>/'__PHP__BLOCK__'.$self->add_php_block($1).'__'/sge;

    # Temporarily replacing DOCTYPE declaration

    $text =~ s/<\!DOCTYPE(.*?)>/'__DOCTYPE__'.$1.'__END_DOCTYPE__'/sge;

    # Replacing the symbolic entities as we are not going to expand them

    $text =~ s/&(\w+);/'__HTML__ENTITY__'.$1.'__'/ge;

    # Wrapping CDATA blocks inside special '__CDATA' tag

    $text =~ s/(<\!\[CDATA\[.*?\]\]>)/<__CDATA>$1<\/__CDATA>/sg;

    # Wrapping HTML comments inside special '__COMMENT' tag

    $text =~ s/<\!--(.*?)-->/<__COMMENT><\!\[CDATA\[$1\]\]><\/__COMMENT>/sg;

    # Now we should properly handle the situation when PHP blocks are inside the <...>
    # This violates the XML rules, so we should dance around this, converting
    # all '__PHP__BLOCK__#__' to ' __PHP__BLOCK__#__="" '. Yeah, weird.

    $in_cdata = undef;
    $in_tag = undef;
    $in_attr = undef;

    $text =~ s/(<\!\[CDATA\[|\]\]>|<|>|"|__PHP__BLOCK__\d+__)/$self->fix_php_blocks($1, \$text)/ge;

    # Extracting strings out of PHP blocks

    foreach my $block (@{$self->{php_blocks}}) {

        # Parsing the $pageTitle variable value
        $block =~ s/(\$pageTitle = ")(.*?)(";)/$1.&$callbackref($self->expand_entities($2), undef, 'Page title', undef, $lang).$3/ge;

        # Parsing underscore functions

        $self->parse_underscore_functions(\$block, $callbackref, $lang);
    }

    # Adding the dummy root tag for XML to be valid
    # (no extra line breaks should be added around these dummy tags,
    # as they will appear in the output before any opening PHP script blocks
    # and may break sending headers from the script)

    $text = "<root>".$text."</root>";

    # Creating XML parser object

    use XML::Parser;
    use XML::Parser::Style::IxTree;
    my $parser = new XML::Parser(Style => 'IxTree', ErrorContext => 4);

    # Parsing XML

    my $tree;
    eval {
        $tree = $parser->parse($text);
    };
    if ($@) {
        my $error_text = $@;
        $error_text =~ s/\t/ /g;
        $error_text =~ s/^\s+//s;

        $self->{errors}->{$self->get_current_file_rel} = $error_text;
        die $error_text;
    }

    # Adding the empty attributes hash to the root tag (for uniform processing)

    unshift @$tree, {};

    # For dummy root tag, reset this tag name to empty value, so it won't get exported

    $tree->[1] = '';

    # Analyze all tags recursively to decide which ones require localization

    $self->analyze_tag_recursively('', $tree);

    # Now, in a second pass, export all localizable strings and generate the localized output

    my $out = $self->render_tag_recursively('', $tree, $callbackref, $lang);

    #TODO: substitute symbolic entities
    #TODO: substitute PHP blocks

    #print "\n******************\n$out\n******************\n";

    return $lang ? $out : undef;
}

sub parse_underscore_functions {
    my ($self, $strref, $callbackref, $lang) = @_;

    # Looking for _("..."), __("...") and ___("...") calls and substituting them with static translated strings: "..."

    $$strref =~ s/(^|[^\w_])_{1,3}\("(.+?)"\)/$1.'"'._escape(&$callbackref($self->expand_entities(_unescape($2)), undef, undef, undef, $lang)).'"'/ge;

    # Same for _('...'), __('...') and ___('...')

    $$strref =~ s/(^|[^\w_])_{1,3}\('(.+?)'\)/$1.'"'._escape(&$callbackref($self->expand_entities(_unescape($2)), undef, undef, undef, $lang)).'"'/ge;
}


sub expand_entities {
    my ($self, $s) = @_;

    if ($self->{data}->{expand_entities}) {
        # preserve basic XML entities (to ensure final XML/HTML is still valid
        $s =~ s/&(gt|lt|amp|quot);/\001$1\002/g;
        $s =~ s/&nbsp;/__HTML__ENTITY__nbsp__/g;
        # decode all numeric and named entities using HTML::Entities
        $s = decode_entities($s, {nbsp => '&nbsp;'});
        # restore basic XML entities back
        $s =~ s/__HTML__ENTITY__nbsp__/&nbsp;/g;
        $s =~ s/\001(gt|lt|amp|quot)\002/&$1;/g;
    }

    return $s;
}

sub _unescape {
    my $s = shift;

    $s =~ s/\\"/"/g;
    $s =~ s/\\'/'/g;

    return $s;
}

sub _escape {
    my $s = shift;

    $s =~ s/"/\\"/g;
    #$s =~ s/'/\\'/g; # not needed, as output strings are enclosed in "..."

    return $s;
}

sub analyze_tag_recursively {
    my ($self, $name, $subtree, $prohibit_translation) = @_;
    my $attrs = $subtree->[0];

    my $can_translate = undef;
    my $will_translate = undef;
    my $contains_translatables = undef;
    my $prohibit_children_translation = undef;

    if (exists $self->{extractable_tags}->{$name}) {
        $can_translate = !$prohibit_translation;
    }

    if (exists $attrs->{lang}) {
        if ($attrs->{lang} eq 'en') {
            $prohibit_translation = undef;
            $will_translate = 1;
        }

        if ($attrs->{lang} ne 'en') {
            $prohibit_translation = 1;
            $will_translate = undef;
        }
    }

    my $some_child_will_translate = undef;

    #print "[1][$name: proh=$prohibit_translation, can=$can_translate, some=$some_child_will_translate, will=$will_translate]\n" if $self->{parent}->{debug};

    if (!$will_translate) {
        for (my $i = 0; $i < (scalar(@$subtree) - 1) / 2; $i++) {
            my $tagname = $subtree->[1 + $i*2];
            my $tagtree = $subtree->[1 + $i*2 + 1];

            if ($tagname ne '0') {
                my ($child_will_translate, $child_contains_translatables) =
                    $self->analyze_tag_recursively($tagname, $tagtree, $prohibit_translation);
                $contains_translatables = 1 if ($child_contains_translatables && !$child_will_translate);
                $some_child_will_translate = 1 if $child_will_translate;
            } else {
                my $str = $tagtree; # this is a string for text nodes

                # Trim the string

                $str =~ s/^[\r\n\t ]+//sg;
                $str =~ s/[\r\n\t ]+$//sg;

                # Only non-empty strings which do not contain php blocks can be translated by default

                $contains_translatables = 1 if $str ne '';
                $prohibit_children_translation = 1 if $str =~ m/\b__PHP__BLOCK__(\d+)__\b/;

                #print "** [$name: can=$can_translate, ctr=$contains_translatables] [$str]\n" if $self->{parent}->{debug};
            }
        }
    }

    $will_translate = 1 if $can_translate && $contains_translatables;
    $will_translate = undef if $prohibit_translation or $prohibit_children_translation or $some_child_will_translate;

    #print "[2][$name: can=$can_translate, ctr=$contains_translatables, some=$some_child_will_translate, will=$will_translate]\n" if $self->{parent}->{debug};

    if ($will_translate) {
        $attrs->{'.translate'} = 1;
    }

    if ($prohibit_translation) {
        $attrs->{'.prohibit'} = 1;
    }

    return ($will_translate or $some_child_will_translate or $prohibit_translation or $prohibit_children_translation, $contains_translatables);
}

sub render_tag_recursively {
    my ($self, $name, $subtree, $callbackref, $lang, $prohibit, $cdata, $context) = @_;
    my $attrs = $subtree->[0];

    my $translate = (exists $attrs->{'.translate'}) && (!exists $attrs->{'.prohibit'}) && !$prohibit;

    # if translation is prohibited for an entire subtree, or if the node is going to be translated
    # as a whole, then prohibit translation of children
    my $prohibit_children = $prohibit || $translate;

    $cdata = 1 if (($name eq '__CDATA') || ($name eq '__COMMENT'));

    # if context or hint attribute is defined, use that instead of current value, even if the new value is empty;
    # for values that represent empty strings, use `undef`

    if (exists $attrs->{context}) {
        $context = $attrs->{context} ne '' ? $attrs->{context} : undef;
    }

    if (exists $attrs->{'data-l10n-context'}) {
        $context = $attrs->{'data-l10n-context'} ne '' ? $attrs->{'data-l10n-context'} : undef;
    }

    my $hint;

    if (exists $attrs->{hint}) {
        $hint = $attrs->{hint} ne '' ? $attrs->{hint} : undef;
    }

    if (exists $attrs->{'data-l10n-hint'}) {
        $hint = $attrs->{'data-l10n-hint'} ne '' ? $attrs->{'data-l10n-hint'} : undef;
    }

    my $inner_xml = '';

    my $subnodes_count = (scalar(@$subtree) - 1) / 2;
    for (my $i = 0; $i < $subnodes_count; $i++) {
        my $tagname = $subtree->[1 + $i*2];
        my $tagtree = $subtree->[1 + $i*2 + 1];

        if ($tagname ne '0') {
            # if we are going to translate this tag as a whole, then prohibit translation for the entire subtree
            $inner_xml .= $self->render_tag_recursively($tagname, $tagtree, $callbackref, $lang, $prohibit_children, $cdata, $context);
        } else {
            # tagtree holds a string for text nodes

            my $str = $tagtree;

            # Escaping unsafe xml chars (excluding quotes)

            xml_escape_strref(\$str, 1) unless $cdata;

            # Reconstructing original XML with PHP blocks and symbolic entities

            $self->reconstruct_xml(\$str);

            # Add the string to a resulting xml

            $inner_xml .= $str;
        }
    }

    # Once the inner html is prepared, pass it through localizer if necessary
    # (We do one exception for <object> tag which we extract as a whole)

    if ($translate && ($name ne 'object') && ($inner_xml ne '')) {
        $inner_xml = &$callbackref($self->expand_entities($inner_xml), $context, $hint, undef, $lang);
    }

    # If this is a <script> tag which is not a part of a translatable string,
    # then extract _("...") style strings from it

    if (!$translate && ($name eq 'script')) {
        $self->parse_underscore_functions(\$inner_xml, $callbackref, $lang);
    }

    #print "::<$name>: $translate\n===\n$inner_xml\n===\n";

    # Determine if attributes require localization.
    # This happens when this is not prohibited explicitly,
    # and there is no explicit instruction to localize the tag
    # or there is an explicit instruction to localize the non-terminal tag
    # (as terminal localizable tags will be extracted later as a whole, with all attributes,
    # so there is no need to extract attributes separately)

    my $e = exists $attrs->{'.translate'};
    my $translate_attrs = (!exists $attrs->{'.prohibit'}) && !$prohibit && (!$e || ($e && $inner_xml));

    # Deleting temporary attributes and special 'lang' and 'context' attributes

    delete $attrs->{'.translate'};
    delete $attrs->{'.prohibit'};
    if (!$self->{leave_attrs}) {
        delete $attrs->{lang};
        delete $attrs->{context};
    }

    # Adjusting <meta http-equiv="Content-Language" content="..." /> (if exists)
    # to have the proper content value, e.g. "pt-br"

    if ((lc($name) eq 'meta') && (lc($attrs->{'http-equiv'}) eq 'content-language')) {
        $attrs->{content} = $lang;
    }

    # Generating the string consisting of [attr="value"] pairs

    my $locale = locale_from_lang($lang);
    my $attrs_text;

    foreach my $key (keys %$attrs) {

        if ($key =~ m/^__PHP__BLOCK__\d+__$/) {

            # Reconstruct PHP block

            $self->reconstruct_xml(\$key);

            $attrs_text .= " $key";
        } else {
            my $val = $attrs->{$key};

            my $val_contains_php = ($val =~ m/__PHP__BLOCK__\d+__/);

            # Escaping unsafe xml chars

            xml_escape_strref(\$val);

            # Reconstructing original XML with PHP blocks and symbolic entities

            $self->reconstruct_xml(\$val);

            # Translate absolute in-site hrefs:
            # /about/... -> /about/%LOCALE%/...

            # (!) disabled as this functionality is moved to the string replacement plugin

            #if (($name eq 'a') && ($key eq 'href')) {
            #  $val =~ s|^/about/(.*)$|/about/$locale/$1|;
            #}

            my $can_translate_attr;

            # Localize `alt' and 'title' attributes if allowed (and if there are no php blocks inside)

            if ($translate_attrs
                    && ($key =~ m/^(alt|title)$/)) {
                $can_translate_attr = 1;
            }

            # Localize 'value' attribute for specific <input> tags

            if ($translate_attrs
                    && (lc($name) eq 'input')
                    && (lc($attrs->{type}) =~ m/^(text|search|email|submit|reset|button)$/)
                    && ($key eq 'value')) {
                $can_translate_attr = 1;
            }

            # Localize 'placeholder' attribute for <input> and <textarea> tags

            if ($translate_attrs
                    && (lc($name) =~ m/^(input|textarea)$/)
                    && ($key eq 'placeholder')) {
                $can_translate_attr = 1;
            }

            # do the translation if the value is not empty and doesn't contain php blocks

            if ($can_translate_attr && ($val ne '') && (!$val_contains_php)) {
                $val = &$callbackref($self->expand_entities($val), $context, "$key attribute", undef, $lang);
            }

            $attrs_text .= " $key=\"$val\"";
        }
    }

    # Construct and return the tag string with its inner xml

    if ($name ne '') {
        my $xml;
        if ($name eq '__CDATA') {
            $xml = '<![CDATA['.$inner_xml.']]>';
        } elsif ($name eq '__COMMENT') {
            $xml = '<!--'.$inner_xml.'-->';
        } else {
            $xml = (($inner_xml ne '') || ($name =~ m/^(a|div|iframe|p|script|span|td|textarea|title|h\d)$/i)) ? "<$name$attrs_text>$inner_xml</$name>" : "<$name$attrs_text \/>";
        }

        # If this is a terminal tag (or <object> tag) that requires localization, extract itself

        if ($translate && (($subnodes_count == 0) || ($name eq 'object'))) {
            $xml = &$callbackref($self->expand_entities($xml), $context, undef, undef, $lang);
        }
        return $xml;
    } else {
        return $inner_xml; # for root tag, return just its inner contents
    }
}

1;