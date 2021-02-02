package Serge::Engine::Plugin::parse_xlsx;
use parent Serge::Engine::Plugin::Base::Parser;
use parent Serge::Interface::PluginHost;

use strict;

use File::Path;
use Serge::Mail;
use Serge::Util qw(normalize_strref);
use Spreadsheet::ParseExcel;
use Spreadsheet::ParseXLSX;
use Spreadsheet::Write;

my $DEFAULT_SHEET_NAME = 'Sheet1';
my $DEFAULT_KEY_TEMPLATE = '%SHEET%:%ROW%:%COL%';

sub name {
    return 'XLS/XLSX parser plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{errors} = {};

    $self->merge_schema({
        header_row        => 'BOOLEAN',

        column_shortcuts  => {
            '*'           => 'STRING',
        },

        columns           => {
            '*'           => {
                is_html   => 'BOOLEAN',
                key       => 'STRING',
                hint      => 'STRING',
            }
        },

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

sub read_file {
    my ($self, $filename, $calc_hash) = @_;
    print ":: parse_xlsx::read_file($filename, $calc_hash)\n";
    return ('', '');
}

sub serialize {
    my ($self, $strref) = @_;
    print ":: parse_xlsx::serialize('$$strref')\n";
    return '';
}

sub write_file {
    my ($self, $filename, $strref) = @_;
    print ":: parse_xlsx::write_file($filename, '$$strref')\n";
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    #my $parser = Loctools::Markdown::Parser->new;
    #my $tree = $parser->parse($$textref);

    #$self->process_tree($tree, $callbackref, $lang);

    #return undef unless $lang;

    #my $builder = Loctools::Markdown::Builder::MD->new;
    #return $builder->build($tree);
    return '';
}

1;