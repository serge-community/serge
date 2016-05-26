#!/usr/bin/env perl

use strict;

use utf8;

# Make script find the plugins properly
# no matter what directory it is running from

BEGIN {
    use Cwd qw(abs_path);
    use File::Basename;
    use File::Spec::Functions qw(catfile);
    unshift(@INC, catfile(dirname(abs_path(__FILE__)), '../../lib'));
}

use Encode::Guess;
use File::Find;
use File::Path;
use File::Spec::Functions qw(rel2abs splitpath catpath);
use XML::Parser;

use Serge::DB::Cached;
my $db = Serge::DB::Cached->new();

# determining the current directory where the script is located

my $SCRIPT_DIR = dirname(abs_path(__FILE__));

my $LANG_MAPPING = {
    'ar-sa' => 'ar',
    'sv-se' => 'sv',
    'ko-kr' => 'ko',
    'ms-my' => 'ms',
};

# Initializing output

$| = 1; # autoflush output
binmode(STDOUT, ':utf8'); # to avoid 'Wide character in print' warning

# reading input parameters

my $known_params = {
    ''           => { 'min_length' => 1 },
    'database'   => { 'min_length' => 1, 'max_length' => 1, 'optional' => 1 },
    'force-lang' => { 'max_length' => 0 },
    'force-same' => { 'max_length' => 0 },
    'as-fuzzy'   => { 'as_fuzzy'   => 0 },
    'overwrite'  => { 'max_length' => 0 },
    'test'       => { 'max_length' => 0 },
    'help'       => { 'max_length' => 0 },
};

my $param = {};

foreach my $arg (@ARGV) {
    if ($arg =~ /^--(\w+.*)$/) {
        my ($key, $val) = split('=', $1, 2);
        my @values = split(',', $val);
        $param->{$key} = \@values;
    } else {
        $param->{''} = [] unless exists $param->{''};
        push (@{$param->{''}}, $arg);
    }
}

if (!exists $param->{''} || exists $param->{help}) {
    print "\n";
    print "Usage: $0 <file1> [file2 ... fileN]\n";
    print "                   [--overwrite] [--force-lang] [--force-same]\n";
    print "                   [--database=<DBI:Driver:source>]\n";
    print "                   [--test]\n";
    print "                   [--help]\n";
    print "\n";
    print "  --overwrite:     Overwrite existing translations\n";
    print "                   Default behavior: only new translations are applied\n";
    print "\n";
    print "  --force-lang:    Force add an unknown language (use only when you are sure\n";
    print "                   that this is a completely new valid language)\n";
    print "                   Default behavior: skip the file with a fatal error\n";
    print "\n";
    print "  --force-same:    Force import translations which are equal to source strings\n";
    print "                   Default behavior: skip such items and display a warning\n";
    print "\n";
    print "  --as-fuzzy:      Import all translations as fuzzy\n";
    print "                   Default behavior: no fuzzy flag is set\n";
    print "\n";
    print "  --test:          Just examine the file for errors. Do not import anything\n";
    print "\n";
    print "  --database:      Optional path to a database file\n";
    print "                   Default: value of 'L10N_DATABASE' environment variable\n";
    print "\n";
    print "  --help:          Show this help and exit\n";
    print "\n";
    exit(1);
}

foreach my $key (keys %$param) {
    if (!exists($known_params->{$key})) {
        die "Unknown parameter '$key'\n";
    }

    my $n = scalar(@{$param->{$key}});
    my $min = $known_params->{$key}->{min_length};
    my $max = $known_params->{$key}->{max_length};

    my $prefix = ($key eq '') ? 'Default list of parameters' : "Parameter '$key'";

    if (($n == 0) && ($known_params->{$key}->{type} eq 'array')) {
        die "$prefix expects at least one value\n";
    }
    if (($n > 0) && ($known_params->{$key}->{type} eq 'flag')) {
        die "$prefix expects no value\n";
    }
    if (exists $known_params->{$key}->{min_length} && ($n < $min)
            && !($n == 0 && exists $known_params->{$key}->{optional})) {
        if ($min == 1) {
            die "$prefix expects at least one value\n";
        } else {
            die "$prefix expects at least $min values\n";
        }
    }
    if (exists $known_params->{$key}->{max_length} && ($n > $max)) {
        if ($max == 0) {
            die "$prefix expects no values\n";
        } elsif ($max == 1) {
            die "$prefix expects exactly one value\n";
        } else {
            die "$prefix expects no more than $max values\n";
        }
    }
}

my $test_mode = exists $param->{test};
my $force_same = exists $param->{'force-same'};
my $as_fuzzy = exists $param->{'as-fuzzy'};

my $current_lang;

my $want_item_id;
my $item_id;
my $last_known_item_id;

my $want_common_text;
my $want_source_text;
my $want_target_text;
my $source_text;
my $target_text;

my $cache = {};

my $db_source = $param->{database}->[0] || $ENV{L10N_DATABASE};
die "Neither --database parameter nor 'L10N_DATABASE' environment variable provided\n" unless $db_source;

# TODO: support specifying database username and password
print "Using database file $db_source\n";
$db->open($db_source);

# read the list of known languages (i.e. having at least one translation)

my %known_languages;

my $sqlquery =
    "SELECT DISTINCT language ".
    "FROM translations ".
    "WHERE translations.string IS NOT NULL ".
    "ORDER BY language";
my $sth = $db->prepare($sqlquery);
$sth->execute || die $sth->errstr;

while (my $hr = $sth->fetchrow_hashref()) {
    $known_languages{$hr->{language}} = 1;
}

$sth->finish;

foreach my $path (@{$param->{''}}) {
    if (-f $path) {
        # if a file was specified and it exists, import just that file
        eval {
            do_import($path);
        };
        if ($@) {
            print "Error: failed to import $path: $@\n";
            next;
        }
    } else {
        my @a;

        if (-d $path) {
        # if a directory was specified and it exists,
        # import all .ttx files from this directory (including subdirectories)
            @a = get_directory_contents($path, '\.ttx$');
        } else {
            #otherwise treat the string as a file mask and import all files
            my ($vol, $dirs, $mask) = splitpath($path);
            $path = catpath($vol, $dirs, '');

            #print "::mask:[$mask]\n";
            #print "::path:[$path]\n";

            $mask =~ s/([\.\-\(\)\[\]])/\\$1/g;
            $mask =~ s/\?/./g;
            $mask =~ s/\*/.*?/g;
            $mask = "^$mask\$";
            #print "::regexp:[$mask]\n";

            @a = get_directory_contents($path, $mask);
        }

        foreach my $file (sort @a) {
            my $fullpath = rel2abs($file, $path);
            eval {
                do_import($fullpath);
            };
            if ($@) {
                print "Error: failed to import $fullpath: $@\n";
                next;
            }
        }
    }
}

$db->close();

print "All done.\n";

sub do_import {
    my $file = shift;

    print "\n";
    print "===========================\n";
    if ($test_mode) {
        print "Examining TTX file: $file\n";
    } else {
        print "Importing TTX file: $file\n";
    }
    print "===========================\n";

    ################
    #return; # DEBUG
    ################

    $last_known_item_id = undef;

    my $parser = new XML::Parser(Style => 'Stream');

    open(FILE, $file) or die "Couldn't open file: $!\n";
    binmode(FILE);
    my $data = join('', <FILE>);
    close(FILE);

    my $decoder = Encode::Guess->guess($data);
    if (ref($decoder)) {
        my $enc = uc($decoder->name);
        print "\tEncoding: $enc\n";
        $data = $decoder->decode($data);
    }

    # some strings may have been split in Trados into separate segments.
    # try to detect such adjoining segments and treat any text content between them
    # (typically whitespace) as a text that belongs to both source and translation.
    # Wrap such text with a special <text>...</text> tag (which is not the part of
    # TTX file format) and process it accordingly.

    $data =~ s|</Tu>([^<>]*?)<Tu\s[^<>]+>|<text>$1</text>|g;

    #print $data;

    $parser->parse($data);
}

sub StartTag { # Stream parser callback
    my ($e, $name) = @_;

    #print "::<$name>\n";

    $want_item_id = undef;

    # if <ut> tag is outside the <Tuv> block and has no Class definition (which we set to 'Comment')
    if (($name eq 'ut') && !$want_source_text && !$want_target_text && !exists $_{Class}) {
        $source_text = undef;
        $target_text = undef;
        $want_item_id = 1;
        return;
    }

    if ($name eq 'text') {
        $want_common_text = 1;
        return;
    }

    if ($name eq 'Tuv') {
        $want_source_text = undef;
        $want_target_text = undef;

        #if (!$item_id) {
        #  print "FATAL: No item_id defined prior to translation block. The file looks malformed. Previous item id: $last_known_item_id\n";
        #  exit(1);
        #}

        my $lang = lc($_{Lang});

        if ($lang eq 'en-us') {
            $want_source_text = 1;
        } else {
            $want_target_text = 1;

            # reduce 'xx-xx' language to just 'xx'
            if ($lang =~ m/^(\w+)-(\w+)$/) {
                $lang = $1 if ($1 eq $2);
            }
            # apply mapping for known languages
            $lang = $LANG_MAPPING->{$lang} if exists $LANG_MAPPING->{$lang};

            if ($lang ne $current_lang) {
                if (exists $known_languages{$lang}) {
                    if (!$test_mode) {
                        preload_items_for_lang($lang);
                    }
                } else {
                    if (!exists $param->{'force-lang'}) {
                        print "FATAL: Unknown language: $lang. You may use --force-lang to force import a new language.\n";
                        exit(1);
                    } else {
                        print "WARNING: Unknown language: $lang, but force mode is enabled.\n";
                    }
                }
                $current_lang = $lang;
            }

            return if $test_mode;

            # skip items that already have translations and which come from an unknown language
            if (
                     (!exists $param->{overwrite} && exists $cache->{$lang}->{$item_id}) ||
                     (!exists $param->{'force-lang'} && !exists($known_languages{$lang}))
                 ) {
                print "\tSKIP: $item_id:$current_lang\n";
                $item_id = undef;
            }

            return;
        }
    }

}

sub Text { # Stream parser callback
    if ($want_item_id) {
        if ($_ + 0 ne $_) {
            print "\tWARNING: item_id is not a valid number: $_\n";
        } else {
            $last_known_item_id = $item_id = $_;
        }
        $want_item_id = undef;
        return;
    }

    if ($want_source_text && $item_id) {
        $source_text .= $_;
        return;
    }

    if ($want_target_text && $item_id) {
        $target_text .= $_;
        return;
    }

    if ($want_common_text && $item_id) {
        $source_text .= $_;
        $target_text .= $_;
        return;
    }

}

sub EndTag { # Stream parser callback
    my ($e, $name) = @_;

    #print "::</$name>\n";

    if ($name eq 'ut') {
        $want_item_id = undef;
        return;
    }

    if ($name eq 'text') {
        $want_common_text = undef;
        return;
    }

    if ($name eq 'Tuv') {
        $want_source_text = undef;
        $want_target_text = undef;
        return;
    }

    if ($name eq 'Tu') {
        return unless $item_id;

        # When exporting TTX files for Trados, we replace newlines with
        # special '{\n}' marker. Now it's time to restore original line-breaks
        # (but first remove real linebreaks that translators may have added)

        $source_text =~ s/\n//sg;
        $target_text =~ s/\n//sg;

        $source_text =~ s/\{\\n\}/\n/g;
        $target_text =~ s/\{\\n\}/\n/g;

        # modify target string whitespace to match the one in the source string

        if ($source_text =~ m/^(\s*).*?(\s*)$/s) {
            my $start = $1;
            my $end = $2;
            $target_text =~ s/^\s*(.*?)\s*$/$start.$1.$end/se;
        }

        # sanity check: check that the source string matches the one in the database

        my ($string) = $db->get_source_string($item_id);
        if ($string ne $source_text) {
            print "\tSKIP: $item_id (source string differs from the one in the database)\n";
            print "\t\t Original: $string\n";
            print "\t\t  In file: $source_text\n";
            $item_id = undef;
            return;
        }

        my $item_props = $db->get_item_props($item_id);

        #use Data::Dumper; print Dumper($item_props);

        if (!$item_props) {
            print "\tSKIP: $item_id (item no loner exists in the database)\n";
        } else {
            my ($string) = $db->get_source_string($item_id);
            if (($string eq $target_text) && !$force_same) {
                print "\tSKIP: $item_id (target string is the same as source string: '$string'). Use --force-same to force import such translations.\n";
            } elsif (!$test_mode) {
                my $notice = $item_props->{orphaned} ? ' (item is orphaned)' : '';
                print "\t$item_id:$current_lang => $target_text$notice\n";
                # set merge flag only in the overwrite mode
                my $merge_flag = exists $param->{overwrite};
                $db->set_translation($item_id, $current_lang, $target_text, $as_fuzzy, undef, $merge_flag); # no comment
            }
        }

        $item_id = undef;
    }

}

# return top-level directory contents (files and folder names)
sub get_directory_contents {
    my ($path, $mask) = @_;
    $path = '.' unless $path;
    $mask = '.' unless $mask;

    my @a;

    find({'wanted' => sub {
        if (($_ ne '.') && ($_ =~ m|$mask|)) {
            push (@a, $_);
        }
    }, 'follow' => 1}, $path);

    return @a;
}

# preload the list of known items which have translations for a given language
sub preload_items_for_lang {
    my ($lang) = @_;

    return if exists $cache->{$lang}; # return if language is already cached
    my $h = $cache->{$lang} = {};

    print "Preloading item cache for language '$lang'...\n";

    utf8::upgrade($lang) if defined $lang;

    my $sqlquery =
        "SELECT t.item_id ".
        "FROM translations t ".

        "JOIN items i ".
        "ON t.item_id = i.id ".

        "JOIN strings s ".
        "ON i.string_id = s.id ".

        "WHERE s.skip = 0 ".
        "AND t.language = ? ".
        "AND t.string IS NOT NULL";

    my $sth = $db->prepare($sqlquery);
    $sth->bind_param(1, $lang) || die $sth->errstr;
    $sth->execute || die $sth->errstr;

    while (my $hr = $sth->fetchrow_hashref()) {
        $h->{$hr->{item_id}} = 1;
    }
    $sth->finish;
    $sth = undef;
}
