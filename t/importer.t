#!/usr/bin/env perl

use strict;

# HOW TO USE THIS TEST
#
# By default, this test runs over all directories in t/data/importer/.  To run
# the test only for specific directories, pass the directory names to this
# script or assign them to the environment variable SERGE_IMPORTER_TESTS as a
# comma-separated list.  The following two examples are equivalent:
#
# perl t/importer.t parse_json parse_strings
# SERGE_IMPORTER_TESTS=parse_json,parse_strings prove t/importer.t

BEGIN {
    use Cwd qw(abs_path);
    use File::Basename;
    use File::Spec::Functions qw(catfile);
    map { unshift(@INC, catfile(dirname(abs_path(__FILE__)), $_)) } qw(lib ../lib);
}

use Data::Dumper;
use File::Copy::Recursive qw/dircopy/;
use File::Find qw(find);
use File::Path;
use File::Spec::Functions qw(catfile);
use Getopt::Long;
use Test::Config;
use Test::Diff;
use Test::More;
use Test::DB::Dumper;
use Serge::Importer;
use Serge::Engine::Job;

$| = 1; # disable output buffering

# to get the same results between tests,
# we override the `file_mtime` function to return a constant value;
# Serge::Importer automatically imports this function from Serge::Util
# (this is why it actually appears in Serge::Importer namespace)
sub Serge::Importer::file_mtime {
    return 12345678;
}

my $this_dir = dirname(abs_path(__FILE__));
my $tests_dir = catfile($this_dir, 'data', 'importer');

my @importer_confs;

my ($init_references);

GetOptions("init" => \$init_references);

my @importer_dirs = @ARGV;
if (my $env_dirs = $ENV{SERGE_IMPORTER_TESTS}) {
    push @importer_dirs, split(/,/, $env_dirs);
}

unless (@importer_dirs) {
    find(sub {
        push @importer_confs, $File::Find::name if(-f $_ && /\.serge$/ && $_ ne 'common.serge');
    }, $tests_dir);
} else {
    for my $dir (@importer_dirs) {
        find(sub {
            push @importer_confs, $File::Find::name if(-f $_ && /\.serge$/ && $_ ne 'common.serge');
        }, catfile($tests_dir, $dir));
    }
}

sub delete_directory {
    my ($path, $ignore_errors) = @_;

    my $err;

    if (-e $path) {
        rmtree($path, { error => \$err });
        if (@$err && !$ignore_errors) {
            my $err_text = '';

            map {
                foreach my $key (keys %$_) {
                    $err_text .= $key.': '.$_->{$key}."\n";
                }
            } @$err;

            BAIL_OUT("Directory '".$path."' couldn't be removed\n$err_text");
        }
    }
}

for my $config_file (@importer_confs) {

    subtest "Test config: $config_file" => sub {
        my $cfg = Test::Config->new($config_file);

        SKIP: {
            my $ok = ok(defined $cfg, 'Config file read');
            skip "<$config_file>", $init_references ? 2 : 4 if !$ok;

            my $err;

            delete_directory($cfg->output_path);
            if ($init_references) {
                delete_directory($cfg->reference_output_path);
            }

            my $engine = Serge::Importer->new();
            $engine->{optimizations} = undef; # force generate all the files
            $cfg->chdir;

            foreach my $job_data (@{$cfg->{data}->{jobs}}) {
                my $job;

                eval {
                    $job = Serge::Engine::Job->new($job_data, $engine, $cfg->{base_dir});
                    $engine->process_job($job);
                };

                if ($@) {
                    my $error = $@;
                    # cleanup error message to avoid having file paths that will differ across installations
                    $error =~ s/\s+$//sg;
                    $error =~ s/ at .*? line \d+\.$//s;
                    $error =~ s/ \(\@INC contains: .*\)$//s;
                    $error =~ s/\@INC.+$/\@INC/s;

                    print "Job '$job_data->{id}' will be skipped: $error\n";

                    eval { mkpath($cfg->errors_path) };
                    die "Couldn't create $cfg->errors_path: $@" if $@;
                    my $filename = catfile($cfg->errors_path, $job_data->{id}.'.txt');
                    open(OUT, ">$filename");
                    binmode(OUT, ':unix :utf8');
                    print OUT $error;
                    close(OUT);
                }
            }

            #ok(!$@, 'Processing all jobs in config file') or BAIL_OUT('Engine failed to run some of the jobs');

            if ($cfg->can_dump_db) {
                my $dumper = Test::DB::Dumper->new($engine);
                $dumper->dump_l10n_tables($Test::DB::Dumper::TYPE_NEAT, $cfg->db_path);
            } else {
                print "Skipped dumping the database, as this is not applicable for this test\n";
            }

            $engine->cleanup;

            if ($init_references) {
                ok(dircopy($cfg->output_path, $cfg->reference_output_path), "Initialized ".$cfg->reference_output_path);
            } else {
                $ok &= dir_diff($cfg->errors_path, $cfg->reference_errors_path, { base_dir => $cfg->{base_dir} } );
                $ok &= dir_diff($cfg->db_path, $cfg->reference_db_path, { base_dir => $cfg->{base_dir} } );
                $ok &= dir_diff($cfg->ts_path, $cfg->reference_ts_path, { base_dir => $cfg->{base_dir} } );
                $ok &= dir_diff($cfg->data_path, $cfg->reference_data_path, { base_dir => $cfg->{base_dir} } ) if $cfg->output_lang_files;
            }

            # Under Windows, deleting just created files may fail with 'Permission denied'
            # for an unknown reason, and only closing the process will release the file handles.
            # Since we will be removing test output at the beginning of each test anyway,
            # don't bail out this time if some files failed to be removed
            delete_directory($cfg->output_path, 1) if $ok;
        }
    }
}


done_testing();
