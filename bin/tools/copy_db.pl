#!/usr/bin/env perl

=head1 NAME

copy_db.pl - Migrate data between translation databases

=head1 DESCRIPTION

B<copy_db.pl> copies all the data in known tables
('files', 'strings', 'items', 'translations' and 'fingerprints')
from source to target translation database.
This is useful when migrating to a new database type (e.g. from SQLite to MySQL).
The target database must exist, but may be empty (in this case the script will populate
its structure). If the target database exists with all the tables needed, the schema
of the copied tables must be the same.

=head1 SYNOPSIS

copy_db.pl
--source=DBI:SQLite:dbname=/path/to/translate.db3
--target=DBI:mysql:database=translate
--target-user=root
--target-password

Use C<--help> option for more information.

Use C<--man> for the full documentation.

=head1 OPTIONS

=over 8

=item B<-?>, B<--help>

Show help on program usage and options.
For a more verbose output, use C<--man>

=item B<--man>

Show all available documentation on this program.

=item B<-s DSN>, B<--source=DSN>

Source database to copy from, as a DBI-compatible connection string.
This parameter is required.

=item B<-su user>, B<--source-user=user>

Source database username (optional; not needed for SQLite databases).

=item B<-sp [password]>, B<--source-password[=password]>

Source database password (optional; not needed for SQLite databases).
If password is ommitted, you will be prompted to enter it securely
(with no echo).

=item B<-t DSN>, B<--target=DSN>

Target database to copy into, as a DBI-compatible connection string.
This parameter is required.

=item B<-tu user>, B<--target-user=user>

Target database username (optional; not needed for SQLite databases).

=item B<-tp [password]>, B<--target-password[=password]>

Target database password (optional; not needed for SQLite databases).
If password is ommitted, you will be prompted to enter it securely
(with no echo).

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

use Data::Dumper;
use DBI ();
use Getopt::Long;

use Serge::DB;
use cli;

my ($source_dsn, $source_user, $source_password, $target_dsn, $target_user, $target_password);

my $result = GetOptions(
    "source|s=s"           => \$source_dsn,
    "source-user|su=s"     => \$source_user,
    "source-password|sp:s" => \$source_password,
    "target|t=s"           => \$target_dsn,
    "target-user|tu=s"     => \$target_user,
    "target-password|tp:s" => \$target_password,
);

if (!$result) {
    cli::error("Failed to parse some command-line parameters.");
}

if (@ARGV > 0) {
    cli::error("Unknown command-line arguments: ".join(' ', @ARGV));
}

if (!$source_dsn || !$target_dsn) {
    cli::error("You must provide at least --source and --target parameters.");
}

print "\nSource: $source_dsn\n";
print "User: $source_user\n" if $source_user;
print "Password: ********\n" if $source_password;

if (defined($source_password) && ($source_password eq '')) {
    $source_password = cli::read_password("Password: ");
}

print "\nTarget: $target_dsn\n";
print "User: $target_user\n" if $target_user;
print "Password: ********\n" if $target_password;

if (defined($target_password) && ($target_password eq '')) {
    $target_password = cli::read_password("Password: ");
}

my $source_db = Serge::DB->new();
my $target_db = Serge::DB->new();

my $SOURCE = $source_db->open($source_dsn, $source_user, $source_password);
my $TARGET = $target_db->open($target_dsn, $target_user, $target_password);

map { copy_data($_) } ('files', 'strings', 'items', 'translations', 'properties');

sub copy_data {
    my ($table) = @_;

    $TARGET->do("BEGIN") or die $TARGET->errstr;
    $TARGET->do("DELETE FROM $table") or die $TARGET->errstr;

    my $sth;

    print "\nFetching table '$table'...";
    my $count = $SOURCE->selectrow_array("SELECT COUNT(id) FROM $table") or die $SOURCE->errstr;
    print " ($count records)\n";
    my $data = $SOURCE->prepare("SELECT * FROM $table") or die $SOURCE->errstr;
    $data->execute() or die $data->errstr;
    my $n = 0;
    while (my $ar = $data->fetchrow_arrayref()) {
        if ($n == 0) {
            my $placeholders_sql = ('?, ' x (scalar(@$ar) - 1)) . '?';
            my $sqlquery = "INSERT INTO $table VALUES ($placeholders_sql)";
            $sth = $TARGET->prepare($sqlquery) or die $TARGET->errstr;
        }
        $n++;
        print "$n of $count\n" if ($n % 1000 == 0 or $n == $count);

        my $i = 0;
        map {
            $i++;
            $sth->bind_param($i, $ar->[$i-1]) or die $sth->errstr;
        } @$ar;

        if (!$sth->execute) {
            print Dumper($ar);
            exit(1);
        };
    }
    $sth->finish;
    $data->finish;

    $TARGET->do("COMMIT") or die $TARGET->errstr;
}