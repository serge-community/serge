#!/usr/bin/env perl

=head1 NAME

normalize_database_whitespace.pl - Normalizes leading/trailing whitespaces for all translations in the database

=head1 DESCRIPTION

B<normalize_database_whitespace.pl> normalizes leading/trailing whitespaces for all translations in the database.
After running this script, run 'serge --recreate-ts-files' to update translation files.

=head1 SYNOPSIS

normalize_database_whitespace.pl
--database=DBI:SQLite:dbname=/path/to/translate.db3
--save-to=output_log.html

Use C<--help> option for more information.

Use C<--man> for the full documentation.

=head1 OPTIONS

=over 8

=item B<-db DSN>, B<--database=DSN>

Database to read statistics from.
This parameter is required.

=item B<-u user>, B<--user=user>

Database username (optional; not needed for SQLite databases).

=item B<-p [password]>, B<--password[=password]>

Database password (optional; not needed for SQLite databases).
If password is ommitted, you will be prompted to enter it securely
(with no echo).

=item B<--server-url=URL>

Server URL. This is used to construct links back to the server.

=item B<--save-to=/path/to/report.html>

If provided, a report will also be saved to a specified HTML file

=item B<--lang=xx[,yy][,zz]>, B<--language=xx[,yy][,zz]>, B<--languages=xx[,yy][,zz]>

An optional comma-separated list of languages to check (by default, goes through all languages).
You can specify either languages or translation identifiers, but not both at the same time.

=item B<--dry-run>

Do not update the database, just generate the output

=item B<--debug>

Print debug output

=item B<-?>, B<--help>

Show help on program usage and options.
For a more verbose output, use C<--man>

=item B<--man>

Show all available documentation on this program.

=back

=cut

use strict;

# Make script find the plugins properly
# no matter what directory it is running from

BEGIN {
    use Cwd qw(abs_path);
    use File::Basename;
    use File::Spec::Functions qw(catfile);
    map { unshift(@INC, catfile(dirname(abs_path(__FILE__)), $_)) } qw(../../lib lib);
}

use File::Path qw/make_path/;
use Getopt::Long;
use IO::File;
use URI::Escape;

use Serge::DB;
use Serge::Util qw(generate_key locale_from_lang xml_escape_strref);

use cli;

$| = 1; # autoflush output
binmode(STDOUT, ':utf8'); # to avoid 'Wide character in print' warning

my $REPORTS = {};

my $db;

my ($database, $user, $password, $save_to,
    @lang, $dry_run, $debug);

my $result = GetOptions(
    "db|database=s"             => \$database,
    "u|user=s"                  => \$user,
    "p|password:s"              => \$password,
    "save-to=s"                 => \$save_to,
    "lang|language|languages=s" => \@lang,
    "dry-run"                   => \$dry_run,
    "debug"                     => \$debug,
);

if (!$result) {
    cli::error("Failed to parse some command-line parameters.");
}

if (@ARGV > 0) {
    cli::error("Unknown command-line arguments: ".join(' ', @ARGV));
}

if (!$database) {
    cli::error("You must provide the --database parameter");
}

# convert arrays to hash to ensure no duplicates
my %lang = map { $_ => 1 } split(/,/, join(',', @lang));

print "\nDatabase: $database\n";
print "User: $user\n" if $user;
print "Password: ********\n" if $password;
print "Languages: ".join(', ', sort keys %lang)."\n" if @lang > 0;

if (defined($password) && ($password eq '')) {
    $password = cli::read_password("Password: ");
}

$db = Serge::DB->new();

$db->open($database, $user, $password);

print "Performing checks...\n";

generate_reports_from_database();

render_reports();

print "All done.\n";

sub generate_reports_from_database {
    # reading the list of languages with non-empty translations

    my $languages_sql = '';
    if (keys %lang > 0) {
        $languages_sql = 'AND translations.language IN ("' . join('","', sort keys %lang).'") ';
    }

    my $sqlquery =
        "SELECT ".
        "translations.id as translation_id, ".
        "translations.language, ".
        "strings.string, strings.context, ".
        "translations.string as translation, ".
        "files.namespace, files.path ".
        "FROM items ".

        "JOIN strings ".
        "ON strings.id = items.string_id ".

        "JOIN translations ".
        "ON translations.item_id = items.id ".

        "JOIN files ".
        "ON files.id = items.file_id ".

        "WHERE items.orphaned = 0 ".
        "AND files.orphaned = 0 ".
        $languages_sql.
        "AND strings.skip = 0 ".
        "AND translations.language IS NOT NULL ".
        "AND translations.string IS NOT NULL";

    my $sth = $db->prepare($sqlquery);
    $sth->execute || die $sth->errstr;

    $sqlquery =
        "UPDATE translations ".
        "SET string = ? ".
        "WHERE translations.id = ?";

    my $update_sth = $db->prepare($sqlquery);

    my %bad;

    print "Scanning strings...\n";
    my $n = 0;
    while (my $hr = $sth->fetchrow_hashref()) {
        print "$n\n" if ($n and $n % 10000 == 0);
        $n++;

        my $lang = $hr->{language};
        my $source = $hr->{string};
        my $translation = $hr->{translation};
        my $translation_id = $hr->{translation_id};

        next if $source eq '/user/month';

        my $normalized_translation = $translation;

        # modify target string whitespace to match the one in the source string

        if ($source =~ m/^(\s*).*?(\s*)$/s) {
            my $start = $1;
            my $end = $2;
            $normalized_translation =~ s/^\s*(.*?)\s*$/$start.$1.$end/se;
        }

        if ($normalized_translation ne $translation) {
            $REPORTS->{$lang} = {} unless exists $REPORTS->{$lang};
            $REPORTS->{$lang}->{$translation_id} = {
                source => $source,
                translation => $translation,
                normalized_translation => $normalized_translation
            };

            if (!$dry_run) {
                $update_sth->bind_param(1, $normalized_translation);
                $update_sth->bind_param(2, $translation_id);
                $update_sth->execute || die $update_sth->errstr;
            }
        }
    }
    $sth->finish;
}

sub render_reports {
    my $html;

    foreach my $lang (sort keys %$REPORTS) {

        $html .= qq|
<tr>
    <td colspan="2" style="padding: 4px; border: 1px solid #999; font-weight: bold; font-size: 120%">$lang</td>
</tr>
|;

        foreach my $id (sort keys %{$REPORTS->{$lang}}) {
            my $data = $REPORTS->{$lang}->{$id};
            my $source = $data->{source};
            my $translation = $data->{translation};
            my $normalized_translation = $data->{normalized_translation};

            _dump_html_encode(\$source);
            _dump_html_encode(\$translation);
            _dump_html_encode(\$normalized_translation);

            _colorize_surrounding_whitespace(\$source);
            _colorize_surrounding_whitespace(\$translation);
            _colorize_surrounding_whitespace(\$normalized_translation);

            my $translation_id = qq|<div style="color: #999; margin: 1em 0; font-size: 75%;">$id</div>|;

            $html .= qq|
<tr>
    <td style="vertical-align: top; width: 50%; padding: 4px; border: 1px solid #999;">$source</td>
    <td style="vertical-align: top; width: 50%; padding: 4px; border: 1px solid #999;">$translation\n$translation_id\n$normalized_translation</td>
</tr>
|;
        }
    }

    $html = qq|
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
</head>
<body style="font-family: sans-serif">
<h1>Normalized whitespace</h1>
<table style="width: 100%">

$html

</table>
</body>
</html>
|;

    # in database mode, always save the report to overwrite the old one
    if ($save_to || $dry_run && ($db || (scalar(keys %$REPORTS) > 0))) {

        unless (-f $save_to) {
            make_path(dirname($save_to));
        }

        open(HTML, ">$save_to");
        binmode(HTML, ':utf8');
        print HTML $html;
        close(HTML);

        print "Saved report to '$save_to'\n";
    }
}

sub _colorize_surrounding_whitespace {
    my $strref = shift;

    if ($$strref =~ m/^(\s*).*?(\s*)$/s) {
        my $start = $1;
        my $end = $2;
        $$strref =~ s/^\s*(.*?)\s*$/_colorize_spaces($start).$1._colorize_spaces($end)/se;
    }
}

sub _colorize_spaces {
    my $s = shift;
    $s =~ s/(\s)/<span style="background-color: yellow; border: 1px solid red; white-space: pre;">$1<\/span>/g;
    return $s;
}

sub _dump_html_encode {
    my ($strref) = @_;
    $$strref =~ s/\&/&amp;/g;
    $$strref =~ s/\"/&quot;/g;
    $$strref =~ s/\</&lt;/g;
    $$strref =~ s/\>/&gt;/g;
    $$strref =~ s/\n/<br\/>/g;
}