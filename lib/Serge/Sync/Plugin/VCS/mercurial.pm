package Serge::Sync::Plugin::VCS::mercurial;
use parent Serge::Sync::Plugin::Base::VCS;

use strict;

use File::Spec::Functions qw(catfile);
use Serge::Util qw(subst_macros);

# named boolean values for clarity
my $CAPTURE = 1;
my $IGNORE_ERRORS = 1;

my $DEFAULT_BRANCH = 'default';

sub name {
    return 'Mercurial sync plugin';
}

sub support_branch_switching {
    return 1;
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        email => 'STRING',
        name => 'STRING'
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

    my ($remote_path, $branch) = split(/#/, $remote_path, 2);
    $branch = $DEFAULT_BRANCH unless $branch;

    return ($remote_path, $branch);
}

# get remote repository URL with an optional #branch_name suffix
sub get_remote_url {
    my ($self, $local_path) = @_;

    # if there's no .hg subfolder, return immediately
    # without running any commands
    return undef unless -d catfile($local_path, 'hg');

    my ($url, $branch);

    # if $local_path points not to a git working copy (e.g. blank directory),
    # git will set errorlevel to 1. So wrap this into eval{} do avoid dying
    # in run_in() function and just return undef

    $url = $self->run_in($local_path, 'hg paths default', $CAPTURE, $IGNORE_ERRORS);
    chomp($url);

    $branch = $self->run_in($local_path, 'hg branch', $CAPTURE, $IGNORE_ERRORS);
    chomp($branch);
    $branch = '' if $branch eq $DEFAULT_BRANCH;

    return $branch ? "$url#$branch" : $url;
}

sub switch_to_branch {
    my ($self, $local_path, $branch) = @_;

    my $heads;
    $heads = $self->run_in($local_path, 'hg branches', $CAPTURE);
    if ($heads !~ m|^\Q$branch\E|m) {
        die "No branch '$branch' found\n";
    }

    $self->run_in($local_path, qq|hg update -C $branch|);
}

sub get_last_revision {
    my ($self, $local_path) = @_;

    my $id = $self->run_in($local_path, 'hg identify --id', $CAPTURE);
    chomp($id);
    die "Failed to get revision ID\n" unless $id ne '';
    return $id;
}

sub status {
    my ($self, $local_path) = @_;

    # just display the summary of this repository (new/changed/deleted files)
    $self->run_in($local_path, 'hg status');
}

sub init_repo {
    my ($self, $local_path, $remote_path, $branch) = @_;

    # cloning just a specific branch will prevent quick branch switching
    #$self->run_in($local_path, qq|hg clone $remote_path --branch $branch .|);

    # instead, clone everything, then select the desired branch
    $self->run_in($local_path, qq|hg clone $remote_path .|);
    $self->switch_to_branch($local_path, $branch);
}

sub delete_unversioned {
    my ($self, $local_path) = @_;

    # remove all untracked files
    # (empty untracked directories are left in the file system, which
    # shouldn't be a problem, though)
    my $output = $self->run_in($local_path, 'hg status -nu', $CAPTURE);
    chomp($output);
    foreach my $rel_path (split(/[\r\n]+/, $output)) {
        my $path = catfile($local_path, $rel_path);
        print "Removing $path\n";
        unlink($path) or die $!;
    }
}

sub add_unversioned {
    my ($self, $local_path) = @_;

    # add all untracked files
    $self->run_in($local_path, 'hg add');
}

sub _username {
    my ($self) = @_;

    if ($self->{data}->{name} ne '') {
        if ($self->{data}->{email} ne '') {
            return qq|--user "$self->{data}->{name} <$self->{data}->{email}>"|;
        }
        return qq|--user "$self->{data}->{name}"|;
    }
    return '';
}

sub checkout {
    my ($self, $local_path, $remote_path, $branch) = @_;

    # pull changes from remote server, abandoning all local changes, if any
    $self->run_in($local_path, qq|hg pull|);
    $self->run_in($local_path, qq|hg update -r $branch -C|);
}

sub commit {
    my ($self, $local_path, $original_remote_path, $message) = @_;

    my ($remote_path, $branch) = $self->split_remote_path_branch($original_remote_path);

    # at this point, we don't have any untracked files; they have been added or deleted,
    # depending on the high-level logic

    # we need to check if there's something to commit
    my $output = $self->run_in($local_path, 'hg status', $CAPTURE); #1:capture
    chomp($output);
    if ($output eq '') {
        print "Nothing to commit\n";
        return;
    }

    # multiline messages are not supported
    $message =~ s/\n/ /sg;
    my $msg_parameters = "-m \"$message\"";

    # commit locally
    $self->run_in($local_path, qq|hg commit $msg_parameters|.$self->_username());

    # fetch changes from remote server
    $self->run_in($local_path, qq|hg pull|);

    # merge changes; resolve conflict using 'theirs' strategy
    $self->run_in($local_path, qq|hg merge -t internal:other|);

    # push changes to the remote server
    $self->run_in($local_path, qq|hg push -b $branch|);
}

1;