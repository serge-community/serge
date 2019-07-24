#!/usr/bin/env perl

use strict;

use utf8;
no utf8; # source is NOT utf8 itself

# Make script find the plugins properly
# no matter what directory it is running from

BEGIN {
    use Cwd qw(abs_path);
    use File::Basename;
    use File::Spec::Functions qw(catfile);
    unshift(@INC, catfile(dirname(abs_path(__FILE__)), '../../lib'));
}

use Encode qw(encode_utf8);
use File::Path;

use Serge::DB;
my $db = Serge::DB->new();

# determining the current directory where the script is located

my $SCRIPT_DIR = dirname(abs_path(__FILE__));

our $OPENED_DUMP_FILES = {};

die "'L10N_DATABASE' environment variable not defined\n" unless exists $ENV{L10N_DATABASE};
our $OUT_PATH = $ARGV[0] || "%LANG%-translations.html";

# Initializing output

$| = 1; # autoflush output
binmode(STDOUT, ':utf8'); # to avoid 'Wide character in print' warning

$db->open($ENV{L10N_DATABASE}, $ENV{L10N_DATABASE_USER}, $ENV{L10N_DATABASE_PASSWORD});

print "Dumping database into html...\n";

dump_database_into_html();

print "All done.\n";

sub dump_database_into_html {
    # reading the list of languages with non-empty translations

    my @lang;

    my $sqlquery =
        "SELECT DISTINCT language ".
        "FROM translations ".
        "WHERE translations.string IS NOT NULL ".
        "ORDER BY language";
    my $sth = $db->prepare($sqlquery);
    $sth->execute || die $sth->errstr;

    my $text;
    while (my $hr = $sth->fetchrow_hashref()) {
        push @lang, $hr->{language};
    }

    $sth->finish;

    foreach my $language (@lang) {

        my $filename = $OUT_PATH;
        $filename =~ s/%LANG%/$language/g;

        my $path = dirname($filename);
        if ($path ne '.') {
            eval { mkpath($path) };
            ($@) && die "Couldn't create $path: $@\n";
        }

        print "\tGenerating $filename\n";

        my $sqlquery =
            "SELECT ".
            "translations.language, ".
            "strings.string, strings.context, ".
            "translations.string as translation, translations.comment, ".
            "files.namespace, files.path, items.hint, items.orphaned ".
            "FROM items ".

            "LEFT OUTER JOIN strings ".
            "ON strings.id = items.string_id ".

            "LEFT OUTER JOIN translations ".
            "ON translations.item_id = items.id ".

            "LEFT OUTER JOIN files ".
            "ON files.id = items.file_id ".

            "WHERE translations.language = ? ".
            "AND strings.skip = 0 ".
            "AND translations.string IS NOT NULL ".
            "ORDER BY ".
            "translations.language, ".
            "strings.string, strings.context, ".
            "items.id, ".
            "files.namespace, files.path";
        my $sth = $db->prepare($sqlquery);
        $sth->bind_param(1, $language) || die $sth->errstr;
        $sth->execute || die $sth->errstr;

        my $html;
        my $lines = [];
        my $prev_key;
        while (my $hr = $sth->fetchrow_hashref()) {
            my $string = $hr->{string};
            my $context = $hr->{context};
            my $translation = $hr->{translation};
            my $comment = $hr->{comment};
            my $key = "$string\001$context\001$translation\001$comment"; # group rows by these criterias
            if ($key ne $prev_key) {
                $html .= _generate_row($lines);
                $lines = [];
                $prev_key = $key;
            }
            push @$lines, $hr;
        }
        $sth->finish;

        $html .= _generate_row($lines) if scalar(@$lines) > 0; # last row

        open(HTML, ">$filename") or die "Can't write to file: $!";
        binmode(HTML, ':utf8');

        print HTML qq{
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<style>

body, code {
    font-family: serif;
}

table {
    width: 100%;
    border-bottom: 1px solid #ddd;
}

td {
    width: 50%;
    padding: 4px;
}

code {
    color: #900;
}

.context {
    color: #99f;
}

.orphaned {
    text-decoration: line-through;
}

.used {
    color: #696;
    font-size: 0.7em;
    margin-top: 0.5em;
}

.comment {
    color: #f99;
    margin-top: 0.5em;
}

</style>

<title>Translated strings for '$language' language</title>
</head>


<body>
<h1>Translated strings for '$language' language</h1>

$html

</body>
</html>
        };

        close(HTML);
    } # foreach language
}

sub _generate_row {
    my ($lines) = @_;

    my @used;
    my $all_orphaned = 1;
    foreach my $hr (@$lines) {
        my $namespace = $hr->{namespace};
        my $path = $hr->{path};
        my $hint = $hr->{hint};
        my $orph = $hr->{orphaned};
        my $line = "$namespace/$path";
        $line .= " ($hint)" if $hint;
        _dump_html_encode(\$line);
        $line = '<span class="orphaned">'.$line.'</span>' if $orph;
        push @used, $line;
        $all_orphaned = undef if (!$orph);
    }

    my $string = $lines->[0]->{string};
    my $context = $lines->[0]->{context};
    my $translation = $lines->[0]->{translation};
    my $comment = $lines->[0]->{comment};

    _dump_html_encode(\$string);
    _dump_html_encode(\$context);
    _dump_html_encode(\$translation);
    _dump_html_encode(\$comment);
    _colorize_html(\$string);
    _colorize_html(\$translation);

    $context = "<div class=\"context\"><em>Context:</em> $context</div>" if $context;
    my $used = "<div class=\"used\">".join('<br />', @used)."</div>" if scalar(@used) > 0;
    $comment = "<div class=\"comment\">$comment</div>" if $comment;
    my $orphaned = ' class="orphaned"' if $all_orphaned;

    return "<table><tr><td$orphaned>$string$context$used</td><td$orphaned>$translation$comment</td></tr></table>\n";
}

sub _dump_html_encode {
    my ($strref) = @_;
    $$strref =~ s/\&/&amp;/g;
    $$strref =~ s/\"/&quot;/g;
    $$strref =~ s/\</&lt;/g;
    $$strref =~ s/\>/&gt;/g;
    $$strref =~ s/\n/<br\/>/g;
}

sub _colorize_html {
    my ($strref) = @_;
    $$strref =~ s/(\\[rnt])/<code>$1<\/code><br\/>/g;
    $$strref =~ s/(&amp;.+?;)/<code>$1<\/code>/g;
    $$strref =~ s/(&lt;.+?&gt;)/<code>$1<\/code>/g;
    $$strref =~ s/(%\w+%)/<code>$1<\/code>/g;
    $$strref =~ s/(%\d+(\$\@){0,1})/<code>$1<\/code>/g;
    $$strref =~ s/(%([%idufs\@]|qu))/<code>$1<\/code>/g;
    $$strref =~ s/(%\{\w+\}\@)/<code>$1<\/code>/g;
    $$strref =~ s/(\{\d+\})/<code>$1<\/code>/g;
    $$strref =~ s/(\{.+?\})/<code>$1<\/code>/g;
    $$strref =~ s/(\[\w+\])/<code>$1<\/code>/g;
    $$strref =~ s/(http[s]{0,1}\:\/\/[\w\d_\?\&\%\;\.\,\+\-\@\/]+)/<code>$1<\/code>/g;
}
