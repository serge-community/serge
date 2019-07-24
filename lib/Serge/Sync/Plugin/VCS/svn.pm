package Serge::Sync::Plugin::VCS::svn;
use parent Serge::Sync::Plugin::Base::VCS;

use strict;

use Config::Neat::Schema;
use File::Path;
use File::Spec::Functions qw(catfile rel2abs);

use Serge::Sync::Util;
use Serge::Util qw(subst_macros);

sub name {
    return 'Subversion sync plugin';
}

sub support_branch_switching {
    return undef;
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        user => 'STRING',
        password => 'STRING'
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    map {
        die "'$_' not defined" unless defined $self->{data}->{$_};
        $self->{data}->{$_} = subst_macros($self->{data}->{$_});
        die "'$_' evaluates to an empty value" if $self->{data}->{$_} eq '';
    } qw(user password);
}

sub get_remote_url {
    my ($self, $local_path) = @_;

    # if there's no .svn subfolder, return immediately
    # without running any commands
    return undef unless -d catfile($local_path, '.svn');

    my $output;

    # if $local_path points not to an svn working copy (e.g. blank directory),
    # svn will set errorlevel to 1. So wrap this into eval{} do avoid dying
    # in run_in() function and just return undef

    eval {
        $output = $self->run_in($local_path, 'svn info --non-interactive', 1); #1:capture
    };

    if ($output =~ m/\nURL:(.*?)\n/) {
        my $url = $1;
        $url =~ s/^\s+//;
        $url =~ s/\s+$//;
        return $url;
    }

    return undef;
}

sub get_last_revision {
    my ($self, $local_path) = @_;

    # run recursively (i.e. for all files)
    # never echo - this output can be huge (several megabytes)
    my $output = $self->run_in($local_path, 'svn info -R --xml --non-interactive"', 1, 1); #1:capture, 1:suppress_echo

    # because of the "mixed revision working copies", the folders' committed revision
    # may be lower than the committed revision of a just committed file.
    # and doing `svn up` to update the folder's revision can't guarantee the there were
    # no updates to these files in between.
    # so scanning all files and finding the biggest revision number seems to be
    # the only solution

    my $rev;
    while ($output =~ m/<commit\s+revision=\"(\d+)\">/g) {
        $rev = $1 if ($1 > $rev);
    }
    return $rev;
}

sub status {
    my ($self, $local_path) = @_;
    $self->run_in($local_path, 'svn status --non-interactive');
}

sub _resolve {
    my ($self, $local_path, $mine) = @_;

    my $strategy = $mine ? 'mine-full' : 'theirs-full';

    $self->run_in($local_path,
        qq|svn resolve . --accept $strategy --recursive --non-interactive|
    );
}

sub init_repo {
    my ($self, $local_path, $remote_path) = @_;
    return $self->checkout($local_path, $remote_path);
}

sub _get_unversioned_paths {
    my ($self, $local_path) = @_;

    my @paths;

    my $output = $self->run_in($local_path, 'svn status --non-interactive', 1); #1:capture

    my @lines = split(/[\r\n]+/, $output);

    foreach my $line (@lines) {
        my ($status, $path) = split(/\s+/, $line, 2);
        next unless ($status eq '?'); # skip all statuses except '?' (not under version control)

        $path = rel2abs($path, $local_path);

        next if ($path eq $local_path); # skip the root path itself
        push(@paths, $path);
    }

    return @paths;
}

sub delete_unversioned {
    my ($self, $local_path) = @_;

    my @paths = $self->_get_unversioned_paths($local_path);

    foreach my $path (@paths) {
        if (-d $path) {
            # directory
            print "Deleting the directory $path\n";
            rmtree($path);
        } elsif (-f $path) {
            # file
            print "Deleting the file $path\n";
            unlink $path || die $!;
        } else {
            die "$path is not a file and not a directory?\n";
        }
    }
}

sub _add {
    my ($self, $local_path) = @_;

    $local_path = escape_path($local_path);

    # add just this specific item (file or directory, without its contents) to svn
    $self->run_cmd(qq|svn add "$local_path" --depth empty --non-interactive|);
}

sub add_unversioned {
    my ($self, $local_path) = @_;

    my @paths = $self->_get_unversioned_paths($local_path);

    foreach my $path (@paths) {
        $self->_add($path);
        # after adding a direcotry, add it's immediate children
        if (-d $path) {
            $self->add_unversioned($path);
        }
    }
}

sub _credentials {
    my ($self) = @_;
    return qq|--username "$self->{data}->{user}" --password "$self->{data}->{password}"|;
}

sub checkout {
    my ($self, $local_path, $remote_path) = @_;

    $self->run_in($local_path,
        qq|svn co "$remote_path" . --force --non-interactive |.$self->_credentials()
    );

    $self->_resolve($local_path); # resolve conflicts using their copy
}

sub _get_externals {
    my ($self, $local_path) = @_;

    my $output = $self->run_in($local_path, 'svn status --non-interactive', 1); #1:capture

    my @externals;
    my @lines = split(/[\r\n]+/, $output);

    foreach my $line (@lines) {
        my ($status, $path) = split(/\s+/, $line, 2);
        next unless ($status eq 'X'); # skip all statuses except 'X' (external)

        $path = rel2abs($path, $local_path);

        if (-d $path) {
            # directory
            push(@externals, $path);
        } else {
            # file
            print "WARNING: reported external '$path' is not a directory?\n";
        }
    }
    return @externals;
}

sub _commit {
    my ($self, $local_path, $remote_path, $message) = @_;

    $self->run_in($local_path,
        qq|svn ci --message "$message" --non-interactive |.$self->_credentials()
    );
}

sub commit {
    my ($self, $local_path, $message) = @_;

    # update the project including externals

    $self->run_in($local_path,
        qq|svn up --force --non-interactive |.$self->_credentials()
    );

    $self->_resolve($local_path, 1); # resolve conflicts using local copy

    # commit base dir (externals will not be committed)

    $self->_commit($local_path, $message);

    # commit externals

    my @externals = $self->_get_externals($local_path);

    foreach my $path (@externals) {
        $self->_commit($path, $message);
    }
}

1;