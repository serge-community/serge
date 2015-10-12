package Serge::Engine::Plugin::parse_pot;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

use Serge::Util qw(glue_plural_string po_serialize_msgstr unescape_strref);

my $MODE_DEFAULT      = 0;
my $MODE_MSGID        = 1;
my $MODE_MSGID_PLURAL = 2;
my $MODE_MSGCTXT      = 3;
my $MODE_MSGSTR       = 4;

sub name {
    return 'Gettext .PO/.POT parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my @out;
    my @comments;
    my ($msgid, $msgid_plural, $msgctxt);
    my $mode = $MODE_DEFAULT;
    my $n = 0;

    my @lines = split(/\n/, $$textref);

    foreach my $line (@lines) {
        $n++;
        my $orig_line = $line;

        $line =~ s/^\s+//g;
        $line =~ s/\s+$//g;

        # blank line
        if ($line eq '') {
            @comments = ();
            $msgid = '';
            $msgid_plural = '';
            $msgctxt = undef;
            $mode = $MODE_DEFAULT;
            push @out, $orig_line;
            next;
        }

        # dev/translator comment or reference
        if (($mode == $MODE_DEFAULT) && ($line =~ m/^#[\.:]?(\s+.+)?$/)) {
            $line =~ s/^#[\.:]?\s*//;
            push @comments, $line;
            push @out, $orig_line;
            next;
        }

        # flags
        if (($mode == $MODE_DEFAULT) && ($line =~ m/^#,/)) {
            push @out, $orig_line;
            next;
        }

        if ($line =~ m/^msgid\s+"(.*)"$/) {
            $mode = $MODE_MSGID;
            $msgid = $1;
            push @out, $orig_line;
            next;
        }

        if ($line =~ m/^msgctxt\s+"(.*)"$/) {
            $mode = $MODE_MSGCTXT;
            $msgctxt = $1;
            push @out, $orig_line;
            next;
        }

        if ($line =~ m/^msgid_plural\s+"(.*)"$/) {
            $mode = $MODE_MSGID_PLURAL;
            $msgid_plural = $1;
            push @out, $orig_line;
            next;
        }

        if ($line =~ m/^msgstr(\[\d+\])?\s+"(.*)"$/) {
            # deal with the header
            if ($msgid eq '') {
                push @out, $orig_line;
                next;
            }

            # skip subsequent msgstr lines
            next if $mode == $MODE_MSGSTR;

            unescape_strref(\$msgid);
            if ($msgid_plural ne '') {
                unescape_strref(\$msgid_plural);
                $msgid = glue_plural_string($msgid, $msgid_plural);
            }
            my $comment = @comments > 0 ? join("\n", @comments) : undef;

            if (!$lang) {
                &$callbackref($msgid, $msgctxt, $comment, undef, undef);
            } else {
                my $translation = &$callbackref($msgid, $msgctxt, $comment, undef, $lang);
                push @out, po_serialize_msgstr($translation);
            }
            $mode = $MODE_MSGSTR;
            next;
        }

        # multiline string part
        if ($line =~ m/^"(.*)"$/) {
            if ($mode == $MODE_MSGID) {
                $msgid .= $1;
                push @out, $orig_line;
                next;
            }

            if ($mode == $MODE_MSGID_PLURAL) {
                $msgid_plural .= $1;
                push @out, $orig_line;
                next;
            }

            if ($mode == $MODE_MSGCTXT) {
                $msgctxt .= $1;
                push @out, $orig_line;
                next;
            }

            # skip original MSGSTR lines
            if ($mode == $MODE_MSGSTR) {
                next;
            }
        }

        die "Failed to parse .PO at line $n: '$orig_line'";
    }

    return $lang ? join("\n", @out) : undef;
}

1;