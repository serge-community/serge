package Serge::Engine::Plugin::control_commands;
use parent Serge::Plugin::Base::Callback;

use strict;
use utf8;

use Serge::Util qw(subst_macros);

sub name {
    return "Do actions based on commands provided in translator's comments";
}

#  Examples:
#
#  Set (or replace existing) extra comment for the entire item (all language-specific units);
#  Text is optional. using just `@` clears the extra comment
#  @ [Text]
#
#  Append extra comment paragraph (`\n\n` + text) for the entire item (all language-specific units)
#  + <Text>
#
#  Add (append) `#tag1` to the end of the text; remove `#tag2`
#  #tag1 -#tag2
#
#  Skip string (mark as skipped in Serge database and remove from all .po files)
#  @skip

#  Rewrite all translations for the same source string with the provided translation value.
#  If translation is empty, this will simply remove the translation
#  @rewrite_all

#  Rewrite all translations for the same source string with the provided value
#  and mark translations as fuzzy. If the translation is empty, this has the same effect
#  as @rewrite_all (because empty translations can't be fuzzy)
#  @rewrite_all_as_fuzzy

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        set_fuzzy_on_comment_change => 'BOOLEAN',
    });

    $self->add({
        rewrite_parsed_ts_file_item => \&rewrite_parsed_ts_file_item
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    $self->{data}->{set_fuzzy_on_comment_change} = 1 unless exists $self->{data}->{set_fuzzy_on_comment_change};
}

sub rewrite_parsed_ts_file_item {
    my ($self, $phase, $file, $lang, $item_id, $strref, $flagsref,
        $translationref, $commentref, $fuzzyref, $item_commentref) = @_;

    my $s = $$commentref;

    #  Set (or replace existing) extra comment for the entire item (all language-specific units);
    #  Text is optional. using just `@` clears the extra comment
    #  @ [Text]
    if ($s =~ m/^@(\s+(.*?))?$/s) {
        my $value = $2;
        $$commentref = undef;

        preprocess_value(\$value);

        print "COMMAND: replace item comment: '$value'\n";

        if ($self->{data}->{set_fuzzy_on_comment_change} && ($value ne '')) {
            $$fuzzyref = 1 if $$translationref ne ''; # for the current unit to match the state in the db
            $self->set_fuzzy_for_all_translations($item_id);
        }

        $$item_commentref = $value;
        return;
    }

    #  Append extra comment paragraph (`\n\n` + text) for the entire item (all language-specific units)
    #  + <Text>
    if ($s =~ m/^\+\s+(.*)$/s) {
        my $value = $1;
        $$commentref = undef;

        preprocess_value(\$value);

        print "COMMAND: append item comment: '$value'\n";

        if ($self->{data}->{set_fuzzy_on_comment_change} && ($value ne '')) {
            $$fuzzyref = 1 if $$translationref ne ''; # for the current unit to match the state in the db
            $self->set_fuzzy_for_all_translations($item_id);
        }

        my $item_props = $self->{parent}->{engine}->{db}->get_item_props($item_id);
        my $comment = $item_props->{comment};

        $comment .= "\n\n" if defined $comment && ($value ne '');
        $comment .= $value;

        $$item_commentref = $comment;
        return;
    }

    #  Rewrite all translations of the same string in the database
    #  with the provided translation
    #  @rewrite_all
    if ($s =~ m/^\@(rewrite_all|rewrite_all_as_fuzzy)$/s) {
        print "COMMAND: replace all translations for '$$strref' with '$$translationref'\n";

        my $tr = $$translationref;
        $tr = undef if $tr eq '';

        $$commentref = undef;

        # if translation itself is empty, we can't simply leave both translation
        # and comment empty, otherwise this situation will be treated as 'no translation'
        # and translations will be substituted again; thus, in this case, we set
        # comment to some meaningful value which is not further treated as a command
        $$commentref = 'Translation removed' unless defined $tr;

        my $where_tr = defined $tr ? 't.string != ?' : 't.string IS NOT NULL';

        my $sqlquery = "
            SELECT t.id
            FROM strings s
            JOIN items i ON i.string_id = s.id
            JOIN translations t ON t.item_id = i.id
            WHERE s.string = ?
            AND t.language = ?
            AND $where_tr
            AND i.id != ?
        ";

        my $sth = $self->{parent}->{engine}->{db}->prepare($sqlquery);

        my $n = 1;
        $sth->bind_param($n++, $$strref) || die $sth->errstr;
        $sth->bind_param($n++, $lang) || die $sth->errstr;
        if (defined $tr) {
            $sth->bind_param($n++, $tr) || die $sth->errstr;
        }
        # skip the item itself, since its translation will be set anyway
        $sth->bind_param($n++, $item_id) || die $sth->errstr;

        $sth->execute || die $sth->errstr;
        my @translation_ids;
        while (my $hr = $sth->fetchrow_hashref()) {
            push @translation_ids, $hr->{id};
        }
        $sth->finish;
        $sth = undef;

        if (scalar @translation_ids > 0) {
            my $extra_msg = $s eq '@rewrite_all_as_fuzzy' ? ' + set fuzzy flag' : '';
            print "Found ", scalar @translation_ids, " translations to replace$extra_msg\n";
            foreach my $id (@translation_ids) {
                my $props = $self->{parent}->{engine}->{db}->get_translation_props($id);
                print "\tTranslation $id (was: '$props->{string}')\n";
                $self->{parent}->{engine}->{db}->update_translation_props($id, {
                    string => $tr,
                    comment => $$commentref,
                    fuzzy => $s eq '@rewrite_all_as_fuzzy' && defined $tr ? 1 : 0,
                    merge => 1
                });
            }
        } else {
            print "No translations to replace\n";
        }
    }
}

sub set_fuzzy_for_all_translations {
    my ($self, $item_id) = @_;

    my $sqlquery = "
        SELECT id
        FROM translations
        WHERE item_id = ?
        AND string IS NOT NULL
        AND string != ''
        AND fuzzy = 0;
    ";

    my $sth = $self->{parent}->{engine}->{db}->prepare($sqlquery);

    $sth->bind_param(1, $item_id) || die $sth->errstr;

    $sth->execute || die $sth->errstr;
    my @translation_ids;
    while (my $hr = $sth->fetchrow_hashref()) {
        push @translation_ids, $hr->{id};
    }
    $sth->finish;
    $sth = undef;

    if (scalar @translation_ids > 0) {
        print "Found ", scalar @translation_ids, " translations to set fuzzy flag for\n";
        foreach my $id (@translation_ids) {
            print "\tSetting fuzzy flag for translation $id\n";
            $self->{parent}->{engine}->{db}->update_translation_props($id, {
                fuzzy => 1
            });
        }
    } else {
        print "No translations to set fuzzy flag for\n";
    }
}

sub preprocess_value {
    my ($sref) = @_;

    # TODO: move this replacement logic into plugin

    # replace links like:
    #     https://www.dropbox.com/s/xxxxxx/foo.png?dl=0
    # with:
    #     https://dl.dropboxusercontent.com/s/xxxxxx/foo.png
    #
    # (see http://ryanmo.co/2013/11/03/dropboxsharedlinks/)

    $$sref =~ s|https://www\.dropbox\.com/s/(.*?)\?dl=0|https://dl.dropboxusercontent.com/s/$1|g;
}

1;