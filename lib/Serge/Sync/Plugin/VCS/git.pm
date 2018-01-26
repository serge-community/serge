package Serge::Sync::Plugin::VCS::git;
use parent Serge::Sync::Plugin::Base::VCS;

use strict;

use File::Spec::Functions qw(catfile);
use Serge::Util qw(subst_macros);

# named boolean values for clarity
my $CAPTURE = 1;
my $IGNORE_ERRORS = 1;

my $DEFAULT_BRANCH = 'master';

sub name {
    return 'Git sync plugin';
}

sub support_branch_switching {
    return 1;
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        clone_params => 'STRING',
        name => 'STRING',
        email => 'STRING'
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    map {
        die "'$_' not defined" unless defined $self->{data}->{$_};
        $self->{data}->{$_} = subst_macros($self->{data}->{$_});
        die "'$_' evaluates to an empty value" if $self->{data}->{$_} eq '';
    } qw(name email);
}

sub split_remote_path_branch {
    my ($self, $remote_path) = @_;

    ($remote_path, my $branch) = split(/#/, $remote_path, 2);
    $branch = $DEFAULT_BRANCH unless $branch;

    return ($remote_path, $branch);
}

# get remote repository URL with an optional #branch_name suffix
sub get_remote_url {
    my ($self, $local_path) = @_;

    # if there's no .git subfolder, return immediately
    # without running any commands
    return undef unless -d catfile($local_path, '.git');

    my ($url, $branch);

    # if $local_path points not to a git working copy (e.g. blank directory),
    # git will set errorlevel to 1. So wrap this into eval{} do avoid dying
    # in run_in() function and just return undef

    $url = $self->run_in($local_path, 'git config --get remote.origin.url', $CAPTURE, $IGNORE_ERRORS);
    chomp($url);

    $branch = $self->run_in($local_path, 'git symbolic-ref -q HEAD', $CAPTURE, $IGNORE_ERRORS);
    chomp($branch);
    if ($branch =~ m|^refs/heads/(.+)$|) {
        $branch = $1;
        $branch = '' if $branch eq $DEFAULT_BRANCH;
    }

    return $branch ? "$url#$branch" : $url;
}

sub switch_to_branch {
    my ($self, $local_path, $branch) = @_;

    my $heads;
    $heads = $self->run_in($local_path, 'git ls-remote --heads --quiet', $CAPTURE);
    if ($heads !~ m|\srefs/heads/\Q$branch\E$|m) {
        die "No remote branch '$branch' found\n";
    }

    $self->run_in($local_path, qq|git checkout $branch|);
    $self->run_in($local_path, qq|git rebase origin/$branch|);
}

sub get_last_revision {
    my ($self, $local_path) = @_;

    my $output = $self->run_in($local_path, 'git rev-parse --verify HEAD', $CAPTURE);
    chomp($output);
    return $output;
}

sub status {
    my ($self, $local_path) = @_;

    # just display the summary of this repository (new/changed/deleted files)
    $self->run_in($local_path, 'git status --porcelain');
}

sub init_repo {
    my ($self, $local_path, $remote_path, $branch) = @_;

    $self->run_in($local_path, qq|git clone $remote_path --branch $branch $self->{data}->{clone_params} .|);

    # if email is provided, set it up as an override for this local repository
    if (exists $self->{data}->{email}) {
        $self->run_in($local_path, qq|git config user.email "$self->{data}->{email}"|);
    }

    # if user name is provided, set it up as an override for this local repository
    if (exists $self->{data}->{name}) {
        $self->run_in($local_path, qq|git config user.name "$self->{data}->{name}"|);
    }
}

sub delete_unversioned {
    my ($self, $local_path) = @_;

    # remove all unversioned files and directories
    $self->run_in($local_path, 'git clean -d --force');
}

sub add_unversioned {
    my ($self, $local_path) = @_;

    # add all unversioned files and directories
    $self->run_in($local_path, 'git add --all .');
}

sub checkout {
    my ($self, $local_path, $remote_path, $branch) = @_;

    # abort unfinished rebase, if any
    # (see https://github.com/git/git/blob/master/git-rebase.sh
    # for how Git itself detects an unfinished rebase)

    if (-d catfile($local_path, ".git/rebase-merge") || -d catfile($local_path, ".git/rebase-apply")) {
        print "Aborting unfinished rebase\n";
        $self->run_in($local_path, qq|git rebase --abort|, undef, $IGNORE_ERRORS);
    }

    # on an empty repo where HEAD doesn't exist (there is no single commit)
    # git will consider this a fatal error and set errorlevel to non-zero value
    # thus, ignoring all errors

    # abandon all local changes, if any
    $self->run_in($local_path, qq|git reset --hard origin/$branch|, undef, $IGNORE_ERRORS);

    # before fetching, remove old conflicting branches, if any
    $self->run_in($local_path, qq|git remote prune origin|);

    # pull changes from remote server
    $self->run_in($local_path, qq|git fetch|);
    $self->run_in($local_path, qq|git rebase origin/$branch|);
}

sub _update_message {
    my ($self, $message) = @_;
    # for vanilla Git, do not alter the message;
    # the Gerrit plugin will append the 'Change-Id: xxxxxx' field to the message
    return $message;
}

sub commit {
    my ($self, $local_path, $original_remote_path, $message) = @_;

    my ($remote_path, $branch) = $self->split_remote_path_branch($original_remote_path);

    # update only previously versioned files, do not add unstaged files
    $self->run_in($local_path, 'git add --update');

    # we need to check if there's something to commit, otherwise git will treat
    # empty commit as fatal error and set errorlevel to non-zero value
    my $output = $self->run_in($local_path, 'git status --porcelain', $CAPTURE); #1:capture
    chomp($output);
    if ($output eq '') {
        print "Nothing to commit\n";
        return;
    }

    # prepare the final message
    $message = $self->_update_message($message);
    # split the multiline message into a series of -m "..." -m "..."
    my $msg_parameters = join(' ', map { "-m \"$_\"" } split(/\n+/s, $message));

    # commit locally
    $self->run_in($local_path, qq|git commit $msg_parameters|);

    # fetch changes from remote server
    $self->run_in($local_path, qq|git fetch|);

    # rebase (do not merge, since merges are incompatible with Gerrit).
    $self->run_in($local_path, qq|git rebase origin/$branch|);

    # push changes to the remote server
    $self->_push($local_path, $original_remote_path, $message);
}

# this method is externalized so that gerrit.pm plugin could override it
sub _push {
    my ($self, $local_path, $remote_path, $message) = @_;

    ($remote_path, my $branch) = $self->split_remote_path_branch($remote_path);

    $self->run_in($local_path, qq|git push origin $branch|);
}

1;