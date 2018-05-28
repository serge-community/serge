package Serge::Engine::Plugin::parse_pot;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

use Encode qw(encode_utf8);

use Serge::Util qw(glue_plural_string split_plural_string
    generate_key po_serialize_msgstr unescape_strref);

my $MODE_DEFAULT      = 0;
my $MODE_MSGID        = 1;
my $MODE_MSGID_PLURAL = 2;
my $MODE_MSGCTXT      = 3;
my $MODE_MSGSTR       = 4;

my $MO_PLURAL_SEPARATOR = chr(0);
my $MO_CTX_SEPARATOR = chr(4);
my $MO_MAGIC = 0x950412de;
my $MO_FORMAT = 0;
my $MO_HEADER_SIZE = 28;

sub name {
    return 'Gettext .PO/.POT parser plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        output_mo_path => 'STRING',
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    if (defined $self->{data}->{output_mo_path}) {
        $self->{strings} = {};
        $self->add('after_save_localized_file', \&after_save_localized_file);
        $self->_add_string([''], '', ["Content-Type: text/plain; charset=utf-8\nContent-Transfer-Encoding: 8bit\n"]);
    }
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

        # non-standard comment lines
        if (($mode == $MODE_DEFAULT) && ($line =~ m/^#(.)\s+/)) {
            print "WARNING: unsupported comment at line $n: $line\n" if $self->{parent}->{debug};
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
                        &$callbackref($str, $msgctxt, $comment, undef, $lang, $key);
                    } else {
                        my $translation = &$callbackref($str, $msgctxt, $comment, undef, $lang, $key);
                        push @out, po_serialize_msgstr($translation);
                        if (exists $self->{strings}) {
                            print ":: translation=[$translation]\n";
                            $self->_add_string(\@msgid, $msgctxt, [split_plural_string($translation)]);
                        }
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

sub _add_string {
    my ($self, $msgidref, $msgctxt, $msgstrref) = @_;
    my $key = join($MO_PLURAL_SEPARATOR, map { encode_utf8($_) } @$msgidref);
    $key = $msgctxt.$MO_CTX_SEPARATOR.$key if $msgctxt ne '';
    $self->{strings}->{$key} = join($MO_PLURAL_SEPARATOR, map { encode_utf8($_) } @$msgstrref);
}

sub _mo_chr {
    return map { pack "N*", $_ } @_;
}

sub _mo_str {
    return shift.chr(0);
}

sub _generate_mo {
    my ($self, $file) = @_;

    # .MO file format documentation:
    # https://www.gnu.org/software/gettext/manual/html_node/MO-Files.html

    my $count = scalar keys %{$self->{strings}};
    my $offset = $MO_HEADER_SIZE + $count * 16;
    my @sorted = sort keys %{$self->{strings}};
    my @translations = map { $self->{strings}->{$_} } @sorted;

    open my $OUT, ">", $file or die "Failed to open file [$file] for writing: $!";
    binmode $OUT;
    print $OUT _mo_chr($MO_MAGIC);
    print $OUT _mo_chr($MO_FORMAT);
    print $OUT _mo_chr($count);
    print $OUT _mo_chr($MO_HEADER_SIZE); # offset of table with original strings
    print $OUT _mo_chr($MO_HEADER_SIZE + $count * 8); # offset of table with translation strings
    print $OUT _mo_chr(0); # size of hashing table (we don't generate it)
    print $OUT _mo_chr($offset); # offset of hashing table (this must be set!)

    foreach (@sorted) {
        my $length = length($_);
        print $OUT _mo_chr($length);
        print $OUT _mo_chr($offset);
        $offset += $length + 1;
    }

    foreach (@translations) {
        my $length = length($_);
        print $OUT _mo_chr($length);
        print $OUT _mo_chr($offset);
        $offset += $length + 1;
    }

    foreach (@sorted) {
        print $OUT _mo_str($_);
    }

    foreach (@translations) {
        print $OUT _mo_str($_);
    }

    close $OUT;
}

sub after_save_localized_file {
    my ($self, $phase, $relfile, $lang, $contentref) = @_;
    my $dstpath = $self->{parent}->{engine}->get_full_output_path($relfile, $lang, $self->{data}->{output_mo_path});
    print "\t\tCompiling $dstpath\n";
    $self->_generate_mo($dstpath);
}

1;