#!/usr/bin/env perl

=head1 NAME

fbcgen.pl - Feature branch config generator.

=head1 DESCRIPTION

B<fbcgen.pl> is a companion tool for `feature_branch` Serge plugin.

It scans the master branch in Git and determines the list of qualifying
branches to run localizations against, and then, based on a provided
Serge config template, generates the actual Serge config suitable
for using with `serge sync` to localize all qualifying branches at once.

Qualifying branches are determined as follows:
1) If branch name matches the $skip_branch_mask, it is skipped.
2) If branch name matches the $unmerged_branch_mask, and it is unmerged
   into a master branch, it is included in branch candidates.
3) If branch name matches $any_branch_mask, it is included
   in branch candidates.
4) If $branch_list_file is defined, the file is loaded and parsed;
   in this file lines starting with `#` are considered comments and skipped;
   other lines are treated as branch names (each line is a branch name);
   if branch name is prefixed with `-`, the branch is skipped;
   otherwise the branch name is added to the list of candidates.
5) for each candidate, up to $commit_depth last commits are analyzed, and commit
   lines formatted with $commit_format that match $skip_commit_mask are skipped
   (this is usually needed to skip commits from l10n robot itself). The date
   of last qualifying commit is checked against $old_branch_threshold,
   to see if the branch is still active.

See sample `myproject.cfg` and `myproject.tmpl` files for more information.

=head1 SYNOPSIS

fbcgen.pl myproject.cfg

=cut

use strict;

use Date::Parse;
use File::Spec::Functions qw(rel2abs);
use File::Basename;

# parameters that must be set in the config, otherwise the script won't run
our $data_dir         = ''; # root directory where the master branch checkout is located
our $template_file    = ''; # where to load Serge config template from
our $output_file      = ''; # where to save the localized Serge config file
our $skip_commit_mask = ''; # filter out commits matching this mask (see $commit_format)

# defaults (may be overridden in the config)
our $calculate_params; # the function that generates additional job config variables to insert into template
our $branch_list_file     = ''; # path to the text file which contains the list of branches to include/exclude
our $old_branch_threshold = 15 * 60*60*24; # after 15 days since last push, the branch is considered "old"
our $commit_format        = "%ce;%ci"; # how to render commits for analysis
our $commit_depth         = 500; # how may latest commits to analyze
our $upstream_name        = 'origin'; # use this upstream name
our $skip_branch_mask     = '^(master|develop)$'; # skip these branches unconditionally
our $unmerged_branch_mask = '^feature/'; # process unmerged branches matching this mask
our $any_branch_mask      = '^release/'; # additionally, process these branches even if they were merged

my $config = $ARGV[0];
if (!$config) {
    print "fbcgen - feature branch config generator\n";
    print "Usage: fbcgen.pl <myproject.cfg>\n\n";
    exit(1);
}

my $config_dir = dirname(rel2abs($config));
chdir($config_dir); # expand paths based on the config location

print "Loading config: $config\n";

eval("require '$config'");
die "Can't load config: $@" if $@;

if (!$data_dir) {
    die "\$data_dir variable is missing in the config";
}
$data_dir = rel2abs($data_dir);
if (!-d $data_dir) {
    die "Data directory $data_dir does not exist";
}

if (!$template_file) {
    die "\$template_file variable is missing in the config";
}
$template_file = rel2abs($template_file);
if (!-f $template_file) {
    die "Template file $template_file does not exist";
}

open (TMPL, $template_file) or die "Failed to open $template_file: $!";
my $tmpl = join("", <TMPL>);
close (TMPL);

my $remotes_tmpl;
if ($tmpl =~ m!\Q/* FBCGEN_BRANCH_REMOTES\E\s(.*?)\Q*/\E!s) {
    $remotes_tmpl = $1;
    $tmpl =~ s!\Q/* FBCGEN_BRANCH_REMOTES\E\s(.*?)\Q*/\E\n*!\$FBCGEN_BRANCH_REMOTES!s;
} else {
    die "/* FBCGEN_BRANCH_REMOTES ... */ block is not present in the template file";
}

my $jobs_tmpl;
if ($tmpl =~ m!\Q/* FBCGEN_BRANCH_JOBS\E\s(.*?)\Q*/\E!s) {
    $jobs_tmpl = $1;
    $tmpl =~ s!\Q/* FBCGEN_BRANCH_JOBS\E\s(.*?)\Q*/\E\n*!\$FBCGEN_BRANCH_JOBS!s;
} else {
    die "/* FBCGEN_BRANCH_JOBS ... */ block is not present in the template file";
}

$remotes_tmpl =~ m/\$FBCGEN_DIR/ && $remotes_tmpl =~ m/\$FBCGEN_BRANCH/ or
    die "Both \$FBCGEN_DIR and \$FBCGEN_BRANCH must be present in FBCGEN_BRANCH_REMOTES block";

$jobs_tmpl =~ m/\$FBCGEN_DIR/ && $jobs_tmpl =~ m/\$FBCGEN_BRANCH/ or
    die "Both \$FBCGEN_DIR and \$FBCGEN_BRANCH must be present in FBCGEN_BRANCH_JOBS block";

if (!$output_file) {
    die "\$output_file variable is missing in the config";
}
$output_file = rel2abs($output_file);

if ($branch_list_file ne '') {
    $branch_list_file = rel2abs($branch_list_file);
    if (!-f $branch_list_file) {
        die "Configuration file $branch_list_file does not exist";
    }
}

if (!$skip_commit_mask) {
    die "\$skip_commit_mask variable is missing in the config";
}

chdir($data_dir);

print "\n";
print "Data directory:    $data_dir\n";
print "Upstream:          $upstream_name\n";
print "Branch list file:  $branch_list_file\n";
print "Template file:     $template_file\n";
print "Output file:       $output_file\n";
print "\n";

print "Cleaning up old remote branch references...\n";
system("git remote prune $upstream_name");
print "Done\n\n";

print "Gathering remote branches...\n";

my $branch_candidates = {};

# list all remote branches that were not merged yet
my $out = `git branch -r --no-merged`;
my @a = parse_lines($out);

foreach my $branch (@a) {
    $branch =~ s!^$upstream_name/!!;
    next if $branch =~ m!$skip_branch_mask!;
    $branch_candidates->{$branch} = 1 if $branch =~ m!$unmerged_branch_mask!;
}

# add all remote release branches even if they were merged
# (because we want to update localizations in active release branches
# regardless of their status)
my $out = `git branch -r`;
my @a = parse_lines($out);

foreach my $branch (@a) {
    $branch =~ s!^$upstream_name/!!;
    next if $branch =~ m!$skip_branch_mask!;
    $branch_candidates->{$branch} = 1 if $branch =~ m!$any_branch_mask!;
}

my $config_branches = {};
if (!$branch_list_file) {
    print "Config file not provided, so no branches will be explicitly added\n";
} else {
    print "Loading config file...\n";
    open(CFG, $branch_list_file) or die "Can't open config file '$branch_list_file': $!";
    binmode CFG, ":utf8";
    while (my $line = <CFG>) {
        $line =~ s/^\s+//sg;
        $line =~ s/\s+$//sg;
        next if $line eq '' || $line =~ m/^\#/;
        my $skip = $line =~ m/^-/;
        $line =~ s/^-//;
        $line =~ s!^$upstream_name/!!;
        $config_branches->{$line} = $skip ? -1 : 0;
    }
    close(CFG);
}

# explicitly extend the list with branches from the config file

foreach my $branch (keys %$config_branches) {
    if (!exists $branch_candidates->{$_} && $config_branches->{$_} == 0) {
        print "Explicitly adding $branch branch to the list of candidates\n";
        $branch_candidates->{$branch} = 1;
    }
}
print "Done\n\n";

# go through found branches

print "Analyzing branches...\n";

my @feature_branches;
my $now = time;

foreach my $branch (sort keys %$branch_candidates) {
    my $skip = $config_branches->{$branch} == -1;

    print "$branch - ";

    if ($skip) {
        print "marked in the config as skipped\n";
        next;
    }

    my $out = `git log --pretty=format:"$commit_format" --max-count=$commit_depth $upstream_name/$branch`;
    my @commits = parse_lines($out);
    my ($upd, $upd_str);
    foreach my $line (@commits) {
        next if $line =~ m!$skip_commit_mask!;
        $line =~ s/^.*?;//;
        $upd_str = $line;
        $upd = str2time($upd_str);
        last;
    }
    if ($upd) {
        if (($now - $upd) > $old_branch_threshold) {
            print "too old (last commit: $upd_str), skipping\n";
            next;
        }
    } else {
        print "can't find any recent qualifying commit, skipping\n";
        next;
    }

    $config_branches->{$branch} = 1; # mark as qualifying

    print "OK\n";
    push @feature_branches, $branch;
}
print "Done\n\n";

foreach my $branch (sort keys %$config_branches) {
    if ($config_branches->{$branch} == 0) {
        print "WARNING: branch '$branch' is no longer qualified but is still listed in the configuration file.\n";
    }
}

@feature_branches = map {
    chomp $_;
    $_;
} @feature_branches;

if (@feature_branches > 0) {
    print "Qualifying branches:\n";

    foreach my $branch (@feature_branches) {
        print "\t$branch\n";
    }
} else {
    print "No qualifying branches found\n";
}

print "Rendering the config...\n";

my @out_remote_paths;
my @out_jobs;

my $width = 0;
map { $width = length($_) if length($_) > $width } @feature_branches;


foreach my $branch (@feature_branches) {
    print "\t$branch\n";
    my $dir = $branch;
    $dir =~ s!/!-!sg;
    $dir = 'branch-'.$dir;
    my $dir_padded = $dir . (' ' x ($width - length($branch)));

    my $params = &$calculate_params($branch);
    $params->{DIR} = $dir;
    $params->{DIR_PADDED} = $dir_padded;
    $params->{BRANCH} = $branch;

    push @out_remote_paths, subst_params(\$remotes_tmpl, $params);
    push @out_jobs, subst_params(\$jobs_tmpl, $params);
}

my $out = subst_params(\$tmpl, {
    BRANCH_REMOTES => join("", @out_remote_paths),
    BRANCH_JOBS => join("", @out_jobs),
});

print "\nSaving $output_file\n";
open(OUT, ">$output_file") or die "Can't write to $output_file: $!";
print OUT "# THIS FILE IS GENERATED AUTOMATICALLY\n\n";
print OUT $out;
close OUT;

print "All done.\n";

sub parse_lines {
    my $output = shift;
    chomp $output;
    my @lines = split(/[\r\n]+/, $output);
    @lines = map {
        $_ =~ s/^\s+//;
        $_ =~ s/\s+$//;
        $_;
    } @lines;
    return @lines;
}

sub _subst_match {
    my ($name, $params) = @_;
    return $params->{$name};
}

sub subst_params {
    my ($tmplref, $params) = @_;
    use Data::Dumper;
    my $s = $$tmplref;
    $s =~ s/\$FBCGEN_([A-Z_]+)/_subst_match($1, $params)/sge;
    return $s;
}