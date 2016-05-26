#!/usr/bin/env perl

=head1 NAME

clear_merge_flags.pl - Clear all merge flags from the database.

=head1 DESCRIPTION

B<clear_merge_flags.pl> will clear all merge flags from the specified database.
This is useful for cleaning up flags from no longer active jobs/languages.

=head1 SYNOPSIS

clear_merge_flags.pl
--database=DBI:SQLite:dbname=/path/to/translate.db3

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

use Getopt::Long;
use Serge::DB;

use cli;

$| = 1; # autoflush output
binmode(STDOUT, ':utf8'); # to avoid 'Wide character in print' warning

my ($database, $user, $password);
my @email_to;

my $result = GetOptions(
    "database|db=s"  => \$database,
    "user|u=s"       => \$user,
    "password|p:s"   => \$password,
);

if (!$result) {
    cli::error("Failed to parse some command-line parameters.");
}

if (@ARGV > 0) {
    cli::error("Unknown command-line arguments: ".join(' ', @ARGV));
}

if (!$database) {
    cli::error("You must provide the --database parameter.");
}

print "\nDatabase: $database\n";
print "User: $user\n" if $user;
print "Password: ********\n" if $password;

if (defined($password) && ($password eq '')) {
    $password = cli::read_password("Password: ");
}

my $db = Serge::DB->new();

$db->open($database, $user, $password);

my $sqlquery =
    "SELECT COUNT(*) as n ".
    "FROM translations ".
    "WHERE merge = 1";

my $sth = $db->prepare($sqlquery);
$sth->execute || die $sth->errstr;

my $count = 0;
if (my $hr = $sth->fetchrow_hashref()) {
    $count = $hr->{n};
}

if ($count) {
    print "Clearing $count flags...";

    my $sqlquery =
        "UPDATE translations ".
        "SET merge = 0 ".
        "WHERE merge = 1";

    my $sth = $db->prepare($sqlquery);
    $sth->execute || die $sth->errstr;

    print " Done\n";
} else {
    print "No merge flags found\n";
}

print "All done.\n";