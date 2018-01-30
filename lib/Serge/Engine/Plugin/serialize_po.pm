package Serge::Engine::Plugin::serialize_po;
use parent Serge::Engine::Plugin::Base::Serializer;

use strict;

use Unicode::Normalize;

use Serge;
use Serge::Util;

sub name {
    return '.PO (Gettext) Serializer';
}

sub serialize {
    my ($self, $units, $file, $lang) = @_;

    my $locale = locale_from_lang($lang);

    my $text = qq|msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"Language: $locale\\n"
"Generated-By: Serge $Serge::VERSION\\n"
|;

    foreach my $unit (@$units) {
        $text .= "\n"; # add whitespace before the entry

        # The ordering of the lines matches the Pootle style and is the following:
        #   # Translator's comments
        #   #. Developer's comments (hints)
        #   #: Reference lines
        #   #, flags
        #   msgid "..."
        #   msgctxt "..."
        #   msgstr "..."

        if ($unit->{comment}) {
            $unit->{comment} =~ s/\n/\n# /sg;
            $text .= '# '.$unit->{comment}."\n";
        }

        my $dev_comment = $unit->{hint};

        if ($dev_comment ne '') {
            $dev_comment =~ s/\n/\n#. /sg;
            $text .= "#. $dev_comment\n";
        }

        $text .= "#: File: $file\n";
        $text .= "#: ID: $unit->{key}\n";
        $text .= "#, fuzzy\n" if $unit->{fuzzy};

        # Print the translation entry

        $text .= "msgctxt ".po_wrap($unit->{context})."\n" if $unit->{context} ne '';
        $text .= join("\n", po_serialize_msgid($unit->{source}))."\n";
        # for now, just use one `msgstr[0]=""` placeholder for plural strings,
        # disregarding the number of plurals supported by a language
        $text .= join("\n", po_serialize_msgstr($unit->{target}, po_is_msgid_plural($unit->{source})))."\n";
    } # foreach

    return $text;
}

sub deserialize {
    my ($self, $textref) = @_;

    my @units;
    my $header_skipped;

    # scan the file and extracting all the entries

    #  Sample entry:
    #
    #  # Optional Translator's comment
    #  #: File: ./_help.pl
    #  #: ID: 7d150b9e4cd75b658d5f8d89300fd697
    #  msgctxt "PageHeading"
    #  msgid "Help"
    #  msgstr "Help"
    #
    #  or
    #
    #  #: File: ./_help.pl
    #  #: ID: 7d150b9e4cd75b658d5f8d89300fd697
    #  msgctxt "PageHeading"
    #  msgid "Help"
    #  msgstr ""
    #  "line1\n"
    #  "line2"
    #  ...

    # normalize line breaks (Windows->Unix)
    $$textref =~ s/\r\n/\n/sg;

    # join multi-line entries
    $$textref =~ s/"\n"//sg;

    my @blocks = split(/\n\n/, $$textref);
    foreach my $block (@blocks) {
        my @lines = split(/\n/, $block);

        my @comments;
        my $key;
        my @strings;
        my @translations;
        my $context;
        my $flags_str;
        my $fuzzy = 0;
        my $skip_system_comment;

        # fix for poedit
        my $key_prefix_line;
        # end fix for poedit

        foreach my $line (@lines) {
            # guard against IME editors inserting bogus unprintable symbols into strings
            # that cause rendered resource files to be invalid.
            $line =~ s/[\000-\011\013-\037]//g;

            # use Unicode::Normalize to recompose (where possible) + reorder canonically the Unicode string
            # this will prevent equivalent Unicode entities from being different in the terms of UTF8 sequences
            $line = NFC($line);

            $skip_system_comment = 1 if ((!$skip_system_comment) && ($line =~ m/^# ===/));
            push (@comments, $1) if (!$skip_system_comment && ($line =~ m/^# (.*)$/));

            # poedit breaks lines like:
            #     #: ID: xxxxxxxxx
            # into two lines:
            #     #: ID:
            #     #: xxxxxxxxx
            # so we need to handle this in order not to reject such files

            # fix for poedit
            if ($key_prefix_line) { # if the previous line was "ID:"
                $key = $1 if $line =~ m/^#: (.*)$/;
            }
            $key_prefix_line = ($line =~ m/^#: ID:$/);
            # end fix for poedit

            $key = $1 if $line =~ m/^#: ID: (.*)$/;
            $strings[0] = $1 if $line =~ m/^msgid "(.*)"$/;
            $strings[1] = $1 if $line =~ m/^msgid_plural "(.*)"$/;
            @translations = ($1) if $line =~ m/^msgstr "(.*)"$/;
            $translations[$1] = ($2) if $line =~ m/^msgstr\[(\d+)\] "(.*)"$/;
            $context = $1 if $line =~ m/^msgctxt "(.*)"$/;
            $flags_str = $1 if $line =~ m/^#, (.*)$/;
        }

        # remove empty trailing comment lines that might have separated user comments from system comments

        while (($#comments >= 0) && ($comments[$#comments] eq '')) {
            pop @comments;
        }

        my $string = glue_plural_string(@strings);
        my $translation = glue_plural_string(@translations);
        my $comment = join("\n", @comments);

        unescape_strref(\$string);
        unescape_strref(\$context);
        unescape_strref(\$translation);

        # Skip blocks where both translation and comment are not set. If one wants to clear the translation,
        # he should at least set the comment (or leave an old one if it existed).

        next unless ($translation or $comment);

        # Skip blocks with no key defined (e.g. header entry)

        if ($string eq '') {
            if (!$header_skipped) {
                $header_skipped = 1;
                next;
            }

            if ($key ne '') {
                # if key is defined for an empty string, just warn that and empty item is found
                # and continue (previously, the script was not safeguarded against empty strings,
                # so there can be such entries which can just be skipped)
                print "\t\t? [empty string] $key\n";
                next;
            } else {
                # but if there is no key set, treat this as a seriously malformed file
                print "ERROR: Malformed entry or header found in the middle of the .po file, skipping the rest of the file\n";
                return;
            }
        }

        # sanity check: skip blocks that have no ID defined

        if ($key eq '') {
            print "\t\t? [empty key]\n";
            next;
        }

        # sanity check: the extracted key should match the generated one for given string/context

        if ($key ne generate_key($string, $context)) {
            print "\t\t? [bad key] $key\n";
            next;
        }

        # read fuzzy flag

        my @flags = split(/,[\t ]*/, lc($flags_str));

        $fuzzy = is_flag_set(\@flags, 'fuzzy');

        # sanity check: fuzzy flag with empty translation makes no sense

        if (!$translation && $fuzzy) {
            print "\t\t? [empty translation marked as fuzzy] $key\n";
            $fuzzy = 0; # clear the fuzzy flag
        }

        push @units, {
            key => $key,
            source => $string,
            context => $context,
            target => $translation,
            comment => $comment, # translator's comments
            fuzzy => $fuzzy,
            flags => \@flags,
        };
    }

    return \@units;
}

1;