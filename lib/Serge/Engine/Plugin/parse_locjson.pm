package Serge::Engine::Plugin::parse_locjson;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

use JSON -support_by_pp; # -support_by_pp is used to make Perl on Mac happy
use Serge::Mail;
use Serge::Util qw(xml_escape_strref wrap);

my $LINE_LENGTH = 50; # as per LocJSON specs

sub name {
    return 'LocJSON parser plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{errors} = {};

    $self->merge_schema({
        remove_properties => 'BOOLEAN',

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

    my $email_subject = $self->{data}->{email_subject} || ("[".$self->{parent}->{id}.']: LocJSON Parse Errors');

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

    # Parse JSON

    my $locjson;
    eval {
        $locjson = from_json($$textref);
    };
    if ($@ || !$locjson) {
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

    if (!exists $locjson->{units}) {
        my $error_text = "`units` section is not present in the file";

        $self->{errors}->{$self->{parent}->{engine}->{current_file_rel}} = $error_text;

        die $error_text;
    }

    foreach my $unit (@{$locjson->{units}}) {
        my $source = join('', @{$unit->{source}});
        my $comments;
        if (exists $unit->{properties} && exists $unit->{properties}->{comments}) {
            $comments = join("\n", @{$unit->{properties}->{comments}});
        }
        my $translation = &$callbackref($source, undef, $comments, undef, $lang, $unit->{key});
        my @lines = wrap($translation, $LINE_LENGTH);
        $unit->{source} = \@lines;

        if ($self->{data}->{remove_properties}) {
            delete $unit->{properties};
        }
    }

    if ($self->{data}->{remove_properties}) {
        delete $locjson->{properties};
    }

    # Per LocJSON specs, sort keys alphabetically and pretty-print with 4 spaces for indentation
    return JSON->new->
        indent(1)->indent_length(4)->space_before(0)->space_after(1)->
        escape_slash(0)->canonical->encode($locjson);
}

1;