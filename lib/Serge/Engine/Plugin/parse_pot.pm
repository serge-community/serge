package Serge::Engine::Plugin::parse_pot;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

use Serge::Util qw(glue_plural_string generate_key po_serialize_msgstr unescape_strref);

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

    print "*** IMPORT MODE ***\n" if $self->{import_mode};

    my @out;
    my @comments;
    my $msgctxt;
    my @msgid;
    my @msgstr;
    my $msgstr_idx = 0;
    my $mode = $MODE_DEFAULT;
    my $n = 0;

    my @lines = split(/\n/, $$textref);
    push @lines, ''; # add extra blank line at the end for parser to catch the last unit
    my $last_line = scalar @lines;

    foreach my $line (@lines) {
        $n++;
        my $orig_line = $line;

        $line =~ s/^\s+//g;
        $line =~ s/\s+$//g;

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
            $msgid[0] = $1;
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
            $msgid[1] = $1;
            push @out, $orig_line;
            next;
        }

        if ($line =~ m/^msgstr(\[(\d+)\])?\s+"(.*)"$/) {
            $mode = $MODE_MSGSTR;

            # deal with the .po file header which has an empty msgid
            if ($msgid[0] eq '') {
                push @out, $orig_line;
                next;
            }

            #print ":: [$2] [$3]\n";
            $msgstr_idx = $2;
            $msgstr[$msgstr_idx] = $3;
            push @out, $orig_line if $self->{import_mode};

            next;
        }

        # multiline string part
        if ($line =~ m/^"(.*)"$/) {
            if ($mode == $MODE_MSGID) {
                $msgid[0] .= $1;
                push @out, $orig_line;
                next;
            }

            if ($mode == $MODE_MSGID_PLURAL) {
                $msgid[1] .= $1;
                push @out, $orig_line;
                next;
            }

            if ($mode == $MODE_MSGCTXT) {
                $msgctxt .= $1;
                push @out, $orig_line;
                next;
            }

            if ($mode == $MODE_MSGSTR) {
                # deal with the .po file header which has an empty msgid
                if ($msgid[0] eq '') {
                    push @out, $orig_line;
                    next;
                }

                $msgstr[$msgstr_idx] .= $1;
                push @out, $orig_line if $self->{import_mode};
                next;
            }
        }

        # empty line denotes the end of the unit
        if ($line eq '') {
            if (scalar(@msgid) > 0 && $msgid[0] ne '') {
                my $msgid_0 = $msgid[0];
                unescape_strref(\$msgid_0);

                # need to use own variable ($x) instead of $_ since Perl would not
                # allow to modify the reference for $_ for missing array entries
                # (when array indexes have gaps)
                @msgid = map { my $x = $_; unescape_strref(\$x); $x } @msgid;
                @msgstr = map { my $x = $_; unescape_strref(\$x); $x } @msgstr;

                my $str = glue_plural_string($self->{import_mode} ? @msgstr : @msgid);
                if ($str ne '') {
                    my $comment = @comments > 0 ? join("\n", @comments) : undef;

                    my $key = generate_key($msgid_0, $msgctxt);
                    if (!$lang or $self->{import_mode}) {
                        &$callbackref($str, $msgctxt, $comment, undef, undef, $key);
                    } else {
                        my $translation = &$callbackref($str, $msgctxt, $comment, undef, $lang, $key);
                        push @out, po_serialize_msgstr($translation);
                    }
                }
            }

            # reset state

            @comments = ();
            @msgid = ();
            @msgstr = ();
            $msgstr_idx = 0;
            $msgctxt = undef;
            $mode = $MODE_DEFAULT;
            push @out, $orig_line unless $n == $last_line; # do not output the extra blank line that we added
            next;
        }

        die "Failed to parse .PO at line $n: '$orig_line'";
    }

    return $lang ? join("\n", @out) : undef;
}

1;