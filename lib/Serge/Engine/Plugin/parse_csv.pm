package Serge::Engine::Plugin::parse_csv;

use 5.10.0;
use strict;
use warnings;

use parent 'Serge::Engine::Plugin::Base::Parser';

use English qw( -no_match_vars );
use Data::Dumper;
use IO::String;
use Serge::Mail;
use Serge::Util qw(xml_escape_strref);

sub name {
    return 'CSV Parser Plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        email_from    => 'STRING',
        email_to      => 'ARRAY',
        email_subject => 'STRING',

        end_of_line    => 'STRING',
        delimiter      => 'STRING',
        escape         => 'STRING',
        quote          => 'STRING',

        column_key     => 'STRING',
        column_string  => 'STRING',
        column_context => 'STRING',
        column_comment => 'STRING',
    });

    $self->add('after_job', \&report_errors);
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    eval('use Text::CSV_XS;');
    die "ERROR: To use parse_csv parser, please install Text::CSV_XS module (run 'cpan Text::CSV_XS')\n" if $@;
}

sub quoted_list_str {
    my ($items) = @_;
    if ($items && @$items > 0) {
        return q{'} . join(q{', '}, @$items) . q{'};
    }
    return '';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;
    my $has_errors = 0;

    eval('use Text::CSV_XS;');
    die $@ if $@;

    die 'callbackref not specified' unless $callbackref;

    my $sep_char           = $self->{data}->{delimiter}         // q{,};
    my $eol                = $self->{data}->{end_of_line}       // $INPUT_RECORD_SEPARATOR;
    my $escape_char        = $self->{data}->{escape}            // q{"};
    my $quote_char         = $self->{data}->{quote}             // q{"};

    my $key_col_name       = lc($self->{data}->{column_key}     // 'Key');
    my $text_col_name      = lc($self->{data}->{column_string}  // 'String');
    my $context_col_name   = lc($self->{data}->{column_context} // $key_col_name);
    my $comment_col_name   = lc($self->{data}->{column_comment} // 'Comment');

    my $csv_fh = IO::String->new($textref);
    my $csv = Text::CSV_XS->new({
        allow_loose_quotes => 1,
        binary             => 1,
        eol                => $eol,
        escape_char        => $escape_char,
        quote_char         => $quote_char,
        sep_char           => $sep_char,
    });

    my @out_lines;

    my @headers;
    my $header_line;
    # Construct hashref of { col_name => position }
    my $col_for = do {
        my $tokens = $csv->getline($csv_fh);
        die "Could not parse the header" if $self->_push_csv_error_and_print($csv);

        my %col_for;
        for(my $i = 0; $i < @$tokens; $i++) {
            $col_for{lc $tokens->[$i]} = $i;
        }

        @headers = @$tokens;
        $csv->combine(@$tokens) or $self->_push_csv_error_and_print($csv);
        $header_line = $csv->string;
        die "Could not parse the header" if $self->_push_csv_error_and_print($csv);
        push @out_lines, $header_line;
        \%col_for;
    };

    my $key_col_idx = $col_for->{$key_col_name};
    if (!defined($key_col_idx)) {
        $self->_push_error_and_die(
            "Couldn't find required field '$key_col_name' in CSV headers " .
            quoted_list_str([(keys %$col_for)]));
    }
    my $text_col_idx = $col_for->{$text_col_name};
    if (!defined($text_col_idx)) {
        $self->_push_error_and_die(
            "Couldn't find required field '$text_col_name' in CSV headers " .
            quoted_list_str([(keys %$col_for)]));
    }
    my $context_col_idx = exists $col_for->{$context_col_name} ? $col_for->{$context_col_name} : -1;
    my $comment_col_idx = exists $col_for->{$comment_col_name} ? $col_for->{$comment_col_name} : -1;

    # When possible, we continue parsing on errors. We still die at the end,
    # but this way we'll show the user all errors in the CSV file in one go,
    # not just the first we encounter.
    LINE:
    while(my $tokens = $csv->getline($csv_fh)) {
        $has_errors++ && next LINE if $self->_push_csv_error_and_print($csv);

        if (@$tokens != @headers) {
            my $line_num = $csv_fh->input_line_number;
            my $num_tokens = @$tokens;
            my $num_headers = @headers;
            $self->_push_error_and_print(
                "Can't parse line $line_num\n" .
                "\tError:    The file has $num_headers header fields, but we found $num_tokens tokens at line $line_num\n" .
                "\tHeaders:  " . join('|', @headers) . "\n" .
                "\tContent:  " . join('|', @$tokens));
            $has_errors = 1;
            next LINE;
        }

        my ($key, $text) = @$tokens[$key_col_idx, $text_col_idx];
        my $context = $context_col_idx >= 0 ? $tokens->[$context_col_idx] : undef;
        my $comment = $comment_col_idx >= 0 ? $tokens->[$comment_col_idx] : undef;

        if (!$lang || $self->{import_mode}) {
            &$callbackref($text, $context, $comment, undef, $lang, $key);
        } else {
            $tokens->[$text_col_idx] = &$callbackref($text, $context, $comment, undef, $lang, $key);
            my $status = $csv->combine(@$tokens);
            $has_errors++ && next LINE if $self->_push_csv_error_and_print($csv);
            push @out_lines, $csv->string;
        }
    }

    if (!$csv->eof) {
        $has_errors++ if $self->_push_csv_error_and_print($csv);
    }

    if ($has_errors) {
        # The errors will be printed or mailed. This isn't the place to display them.
        die "Encountered errors. Cannot continue";
    }

    if (!$lang || $self->{import_mode}) {
        return $$textref;
    } else {
        # $csv->combine() adds end-of-line characters so don't join on
        # newline here.
        return join('', @out_lines);
    }
}

sub report_errors {
    my ($self, $phase) = @_;

    my $email_from = $self->{data}->{email_from};
    if (!$email_from) {
        $self->{_csv_errors} = {};
        return;
    }

    my $email_to = $self->{data}->{email_to};
    if (!$email_to) {
        $self->{_csv_errors} = {};
        return;
    }

    my $email_subject = $self->{data}->{email_subject}
        || "[$self->{parent}->{id}]: Serge CSV Parse Errors";

    my $text;
    foreach my $key (sort keys %{$self->{_csv_errors}}) {
        $text .= "<hr />\n<p><b style='color: red'>$key</b>\n";
        my $messages = $self->{_csv_errors}->{$key};
        foreach my $message (@$messages) {
            xml_escape_strref(\$message);
            $text .= "<pre>$message</pre></p>\n";
        }
    }

    $self->{_csv_errors} = {};

    if ($text) {
        $text = qq|
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
</head>
<body style="font-family: sans-serif; font-size: 120%">

<p>

The following parsing errors were found when attempting to localize CSV files.
</p>

$text

</body>
</html>
|;

        Serge::Mail::send_html_message(
            $email_from,
            $email_to,
            $email_subject,
            $text
        );
    }

    return;
}

sub _push_error {
    my ($self, $message) = @_;
    push @{$self->{_csv_errors}->{$self->_mail_key}}, $message;
    return;
}

sub _push_error_and_print {
    my ($self, $message) = @_;
    $self->_push_error($message);
    print "Error: ${\$self->_mail_key}: $message\n";
    return;
}

sub _push_csv_error_and_print {
    my ($self, $csv) = @_;

    if (my $error = $csv->error_diag) {
        my (undef, undef, $bad_part) = $csv->error_diag;
        my $formatted_error = "Error at line $INPUT_LINE_NUMBER:\n" .
            "\tError:   " . $csv->error_diag . "\n" .
            "\tContent: " . $csv->error_input;
        $self->_push_error_and_print($formatted_error);
        return 1;
    }

    return 0;
}

sub _push_error_and_die {
    my ($self, $message) = @_;
    $self->_push_error($message);
    die "Error: ${\$self->_mail_key}: $message";
}

sub _mail_key {
    my ($self) = @_;
    return $self->{parent}->{engine}->{current_file_rel};
}

1;