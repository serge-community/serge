#!/usr/bin/env perl

=head1 NAME

guess_transformation.pl - Run transformation plugin against the given string.

=head1 DESCRIPTION

B<guess_transformation.pl> This script is a command-line wrapper against 'transform' plugin
functionality. It allows you to test how the plugin works against any given string.

=head1 SYNOPSIS

guess_transformation.pl "string" language [--no-uncertain]

Use C<--help> option for more information.

Use C<--man> for the full documentation.

=head1 OPTIONS

=over 8

=item B<string>

<string> is a source string to guess translation for.

=item B<language>

<string> is a target translation language.

=item B<no-uncertain>

If this switch is provided, emulate a 'reuse_uncertain => NO' mode on a job;
in other words, do not use any translation if there are multiple translations
provided for the same source string.

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

use utf8;

use cli;
use Getopt::Long;
use Serge::DB::Cached;
use Serge::Engine::Plugin::transform;

$| = 1; # disable buffered output
binmode(STDOUT, ':utf8'); # to avoid 'Wide character in print' warning

my $string = $ARGV[0];
my $language = $ARGV[1];

if ($string eq '' or $language eq '') {
    cli::error("You must provide the source string and output language");
}

my $no_uncertain;

my $result = GetOptions(
    "no-uncertain" => \$no_uncertain,
);

if (!$result) {
    cli::error("Failed to parse some command-line parameters.");
}
my $db = Serge::DB::Cached->new();

die "'L10N_DATABASE' environment variable not defined\n" unless exists $ENV{'L10N_DATABASE'};
$db->open($ENV{'L10N_DATABASE'}, $ENV{'L10N_DATABASE_USER'}, $ENV{'L10N_DATABASE_PASSWORD'});

my $plugin = new Serge::Engine::Plugin::transform({
    debug => 1,
    reuse_uncertain => !$no_uncertain,
    engine => {
        db => $db
    }
});

$plugin->init();

my ($result) = $plugin->get_translation('get_translation', $string, undef, undef, undef, $language);

my $filtered = Serge::Engine::Plugin::transform::_filter_string($string);
print "Filtered string: '$filtered'\n";
print $result ne '' ? "\nResult for '$language' language: '$result'\n" : "\nNo result found for '$language' language\n";