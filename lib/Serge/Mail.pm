package Serge::Mail;

use strict;

no warnings qw(uninitialized);

use MIME::Lite;
use Net::SMTP;

our $debug    = $ENV{SMTP_DEBUG} == 1;
our $disable  = $ENV{SMTP_DISABLE} == 1;
our $force_to = $ENV{SMTP_FORCE_RECIPIENTS};

our $host     = $ENV{SMTP_HOST} || 'localhost';
our $port     = $ENV{SMTP_PORT} || 25;
our $user     = $ENV{SMTP_USERNAME};
our $pass     = $ENV{SMTP_PASSWORD};

if ($pass && !$user || $user && !$pass) {
    die "Both SMTP_PASSWORD and SMTP_USERNAME should be provided (or neither one)";
}

our $use_ssl = ($port == 465); # autodetect
$use_ssl = ($ENV{SMTP_USE_SSL} == 1) if exists $ENV{SMTP_USE_SSL};
$use_ssl = undef if exists $ENV{SMTP_NO_SSL};

if ($debug) {
    print "SMTP Host: $host\n";
    print "SMTP Port: $port\n";
    print "SMTP SSL : ".($use_ssl ? 'YES' : 'NO')."\n";
    print "SMTP User: $user\n" if $user;
}

sub _send {
    my ($from, $toref, $ccref, $bccref, $data) = @_;

    if ($disable) {
        print "Warning: email will not be sent because of SMTP_DISABLE environment variable\n";
        return;
    }

    my $smtp = Net::SMTP->new($host, Port => $port, SSL => $use_ssl, Debug => $debug);
    if ($@) {
        warn "Failed to send the following email:\n$data\n";
        warn $@;
    }

    if ($user) {
        $smtp->auth($user, $pass) or die "auth() call failed for user '$user'";
    }
    $smtp->mail("$from\n") or die "mail(from) call failed; from='$from'";

    my @to = @$toref;
    if ($force_to) {
        @to = split(',', $force_to);
        print "Warning: the list of email recipients is overridden by SMTP_FORCE_RECIPIENTS environment variable\n";
        print "Email will be sent to: ", join(', ', sort @to), "\n";
    }
    foreach my $recpt (@to) {
        $smtp->to($recpt) or die "to(rcpt) call failed; rcpt='$recpt'";
    }
    if (defined($ccref)) {
        foreach my $recpt (@$ccref) {
            $smtp->cc($recpt) or die "cc(rcpt) call failed; rcpt='$recpt'";
        }
    }
    if (defined($bccref)) {
        foreach my $recpt (@$bccref) {
            $smtp->bcc($recpt) or die "bcc(rcpt) call failed; rcpt='$recpt'";
        }
    }
    $smtp->data() or die "data() call failed";
    $smtp->datasend($data) or die "datasend() call failed";
    $smtp->dataend() or die "dataend() call failed";
    $smtp->quit() or die "quit() call failed";
}

sub sendmessage {
    my ($from, $toref, $subject, $body, $ccref, $bccref) = @_;

    $body =
        "From: $from\n".
        "To: ".join(', ', @$toref)."\n".
        "Cc: ". (defined($ccref) ? join(', ', @$ccref) : '') ."\n".
        "Bcc: ". (defined($bccref) ? join(', ', @$bccref) : '') ."\n".
        "Subject: $subject\n".
        "\n".
        "$body\n";

    _send($from, $toref, $ccref, $bccref, $body);
}

sub send_html_message {
    my ($from, $toref, $subject, $body, $ccref, $bccref) = @_;

    ### Create a new multipart message:
    my $msg = MIME::Lite->new(
        From    => $from,
        To      => join(', ', @$toref),
        Cc      => defined($ccref) ? join(', ', @$ccref) : '',
        Bcc     => defined($bccref) ? join(', ', @$bccref) : '',
        Subject => $subject,
        Type    => 'multipart/mixed'
    );

    $msg->attach(
        Type => 'text/html; charset=utf-8',
        Data => $body
    );

    _send($from, $toref, $ccref, $bccref, $msg->as_string);
}

1;