package Serge::Util::WordStats;

use strict;
use utf8;

our @ISA = qw(Exporter);

our @EXPORT = qw(
    wordcount
    get_wordcount_chunks
    count_words
);

sub wordcount {
    my $string = shift;

    my $chunks = get_wordcount_chunks($string);

    return count_words($chunks);
}

sub get_wordcount_chunks {
    my $string = shift;

    # As Trados seems to be buggy when it comes to translating
    # multiline strings, replace newlines with special '{\n}' marker
    # which we then will mark as non-translatable


    $string =~ s/\n/{\\n}/g;

    my $chunks = [{
        'translate' => 1,
        'string' => $string
        }
    ];

    find_placeholders($chunks, '&lt;\/?[\w]+.*?>'); # escaped XML tags (used in some strings)
    find_placeholders($chunks, '<\/?[\w]+.*?>'); # XML tags
    find_placeholders($chunks, '\\\{\d+\\\}|\{\d+\}'); # Java format and it's escaped version
    find_placeholders($chunks, '\$\{[\w\.\:]+\}'); # template format
    find_placeholders($chunks, '%\d\$\w'); # Android format
    find_placeholders($chunks, '%[\d]*(?:.\d+)*(?:h|l|I|I32|I64)*[cdiouxefgns]'); # sprintf
    find_placeholders($chunks, '%@'); # Objective C style placeholders
    find_placeholders($chunks, '\$[\w\d]+?\$'); # dollar sign placeholders
    find_placeholders($chunks, '\%[\w\d]+?\%'); # percent sign placeholders
    find_placeholders($chunks, '\{\\\n\}'); # '{\n}' newline marker
    find_placeholders($chunks, '\\\+[rnt]'); # escaping sequences (\n, \r, \t)
    find_placeholders($chunks, '&#\d+;|&\w+;'); # XML entities
    find_placeholders($chunks, 'Evernote International|Evernote Food|Evernote Hello|Evernote Clearly|Evernote Business|Skitch|Evernote®?|Food|^Hello$|Clearly'); # product names
    find_placeholders($chunks, 'Ctrl\+\w$|Shift\+\w$|Alt\+\w$'); # Shortcuts
    find_placeholders($chunks, 'Ctrl\+$|Shift\+$|Alt\+$'); # Shortcut modifiers
    #find_placeholders($chunks, '^["\']+|["\']+$'); # surrounding quotes (including ones around placeholders)
    #find_placeholders($chunks, '^\.$'); # end punctuation after (or between) placeholders

    # find patterns that are not counted as words in Trados
    find_placeholders($chunks, '^[^\w\&]\s|\s[^\w\&]\s|\s[^\w\&]$|^[^\w\&]$', 'dont-count'); # hanging symbols (excluding a-z, _ and &)
    #use Data::Dumper; print Dumper($aref);

    return $chunks;
}


sub count_words {
    my ($chunks) = @_;

    # These rules are based on observed Trados 2007 word calculation behavior
    my $remove = qr{[\.]+}; # dots
    my $delimiters = qr{\W+}; # anything except a-z, A-Z and _ ( \W doesn't work inside [...] )
    my $english_date = qr{(^|\W)(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+(?:\d{2})?\d{2}(\W|$)};

    my $n = 0;

    foreach my $chunk (@$chunks) {
        if ($chunk->{translate}) {
            my $s = $chunk->{string};
            $s =~ s/$english_date/$1$2$3/g; # replace the date with just the month name (i.e. count as a single word)

            #print "::[$s]\n";

            $s =~ s/$remove//g;
            $s =~ s/^$delimiters//;
            $s =~ s/$delimiters$//;
            my @a = split(/$delimiters/, $s);
            #print "!!!\n".join("<\n>", @a)."\n!!!\n";
            $n += scalar(@a);
        }
    }

    return $n;
}


sub find_placeholders {
    my ($aref, $regex, $class) = @_;

    my $i = 0;
    while ($i < scalar(@$aref)) {
        my $chunk = $aref->[$i];
        if (!$chunk->{translate}) {
            $i++;
        } else {
            my @subchunks = split(/($regex)/, $chunk->{string});
            my @a;
            my $translate;
            foreach my $subchunk (@subchunks) {
                $translate = !$translate;
                push @a, {'translate' => $translate, 'string' => $subchunk, 'class' => $class};
            }
            splice(@$aref, $i, 1, @a);
            $i += scalar(@a);
        }
    }
}

1;
