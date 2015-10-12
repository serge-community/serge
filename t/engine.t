#!/usr/bin/perl

use strict;

BEGIN {
    use File::Basename;
    use File::Spec::Functions qw(rel2abs catfile);
    map { unshift(@INC, catfile(dirname(rel2abs(__FILE__)), $_)) } qw(lib ../lib);
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
use Serge::Engine;
use Serge::Engine::Processor;

$| = 1; # disable output buffering

# to get the same results between tests,
# we override the `file_mtime` function to return a constant value;
# Serge::Engine automatically imports this function from Serge::Util
# (this is why it actually appears in Serge::Engine namespace)
sub Serge::Engine::file_mtime {
    return 12345678;
}

my $thisdir = dirname(rel2abs(__FILE__));

my @confs;

my ($init_references);

GetOptions("init" => \$init_references);

my @dirs = @ARGV;

unless (@dirs) {
    find(sub {
        push @confs, $File::Find::name if(-f $_ && /\.serge$/ && $_ ne 'common.serge');
    }, $thisdir);
} else {
    for my $dir (@dirs) {
        find(sub {
            push @confs, $File::Find::name if(-f $_ && /\.serge$/ && $_ ne 'common.serge');
        }, catfile($thisdir, "data/engine", $dir));
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


for my $config_file (@confs) {

    subtest "Test config: $config_file" => sub {
        my $cfg = Test::Config->new($config_file);

        SKIP: {
            my $ok = ok(defined $cfg, 'Config file read');
            skip "<$config_file>", $init_references ? 2 : 4 if !$ok || !$cfg->is_active;

            my $err;

            delete_directory($cfg->output_path);
            if ($init_references) {
                delete_directory($cfg->reference_output_path);
            }

            my $engine = Serge::Engine->new();
            $engine->{optimizations} = undef; # force generate all the files
            my $config = Serge::Config->new($config_file);
            my $processor = Serge::Engine::Processor->new($engine, $config);

            eval {
                $processor->run();
            };
            print "Error: $@" if $@;

            ok(!$@, 'Processing all jobs in config file') or BAIL_OUT('Engine failed to run some of the jobs');

            my $dumper = Test::DB::Dumper->new($engine);
            $dumper->dump_l10n_tables($Test::DB::Dumper::TYPE_NEAT, $cfg->db_path);

            $engine->cleanup;

            if ($init_references) {
                ok(dircopy($cfg->output_path, $cfg->reference_output_path), "Initialized ".$cfg->reference_output_path);
            } else {
                $ok &= dir_diff($cfg->db_path, $cfg->reference_db_path, { base_dir => $cfg->{base_dir} } );
                $ok &= dir_diff($cfg->ts_path, $cfg->reference_ts_path, { base_dir => $cfg->{base_dir} } );
                if (-d $cfg->reference_data_path) {
                    $ok &= dir_diff($cfg->data_path, $cfg->reference_data_path, { base_dir => $cfg->{base_dir} } ) if $cfg->output_lang_files;
                } else {
                    ok(!-d $cfg->data_path, "Directory with localized files shouldn't exist");
                }
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
