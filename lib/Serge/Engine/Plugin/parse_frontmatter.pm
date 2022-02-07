package Serge::Engine::Plugin::parse_frontmatter;
use parent Serge::Engine::Plugin::Base::Parser;
use parent Serge::Interface::PluginHost;

use strict;

use File::Path;
use Serge::Mail;
use Serge::Util qw(normalize_strref);

sub name {
    return 'Front-matter parser plugin';
}

# Reference:
#
# Jekyll: Front Matter
#       https://jekyllrb.com/docs/front-matter/

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{errors} = {};

    $self->merge_schema({
        separator         => 'STRING',

        email_from        => 'STRING',
        email_to          => 'ARRAY',
        email_subject     => 'STRING',

        parser            => {
            plugin        => 'STRING',

            data          => {
               '*'        => 'DATA',
            }
        }

        body_parser       => {
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
    if (defined $self->{parser}->{errors}) {
        my @keys = keys %{$self->{parser}->{errors}};
        if (scalar @keys > 0) {
            map {
                $self->{errors}->{$_} = $self->{parser}->{errors}->{$_};
            } @keys;
            $self->{parser}->{errors} = {};
        }
    }

    if (defined $self->{body_parser}->{errors}) {
        my @keys = keys %{$self->{body_parser}->{errors}};
        if (scalar @keys > 0) {
            map {
                $self->{errors}->{$_} = $self->{body_parser}->{errors}->{$_};
            } @keys;
            $self->{body_parser}->{errors} = {};
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

    my $email_subject = $self->{data}->{email_subject} || ("[".$self->{parent}->{id}.']: Front-Matter Plugin Parse Errors');

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

    $self->{parser} = $self->load_plugin_from_node(
        'Serge::Engine::Plugin', $self->{data}->{parser}
    );

    $self->{body_parser} = $self->load_plugin_from_node(
        'Serge::Engine::Plugin', $self->{data}->{body_parser}
    );

    my $separator = $self->{data}->{separator};
    $separator = '---' if $separator eq '';

    my $frontmatter = '';
    my $body = $$textref;
    if ($markdown =~ m/^$separator\n+(.*)\n+$separator\n+/s) {
        $frontmatter = $1;
        $body =~ s/^$separator\n+.*\n+$separator\n+//s;
    }

    if ($frontmatter ne '') {
        $self->{parser}->{current_file_rel} = $self->{parent}->{engine}->{current_file_rel}.":front-matter";
        $frontmatter = $self->{parser}->parse(\$frontmatter, $callbackref, $lang);
    }

    $self->{body_parser}->{current_file_rel} = $self->{parent}->{engine}->{current_file_rel}.":body";
    $body = $self->{body_parser}->parse(\$frontmatter, $callbackref, $lang);

    return undef unless $lang;

    if ($frontmatter ne '') {
        $body = "$separator\n$frontmatter\n$separator\n\n$body";
    }
    return $body;
}

1;