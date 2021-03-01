package Serge::Sync::Plugin::Base::VCS;
use parent Serge::Plugin::Base, Serge::Interface::SysCmdRunner;

use strict;

use File::Path;
use Serge::Sync::Util qw(get_directory_contents);
use Serge::Util qw(normalize_path subst_macros);

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{initialize} = undef; # set to 1 externally to allow data directory initialization

    $self->merge_schema({
        add_unversioned => 'BOOLEAN',
        name            => 'STRING',
        email           => 'STRING',
        local_path      => 'STRING',
        commit_message  => 'STRING',
        remote_path => {
            ''          => 'STRING_OR_HASH',
            '*'         => 'STRING',
        }
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    # Check job config validity

    map {
        die "'$_' not defined" unless defined $self->{data}->{$_};
        $self->{data}->{$_} = subst_macros($self->{data}->{$_});
        die "'$_' evaluates to an empty value" if $self->{data}->{$_} eq '';
    } qw(local_path remote_path);

    $self->{data}->{local_path} = normalize_path($self->{parent}->abspath($self->{data}->{local_path}));

    $self->{data}->{commit_message} = 'Automatic commit of updated project files' unless defined $self->{data}->{commit_message};

    # 'path' can be either a scalar (string) or a hash { subdir => value },
    # so normalizing scalar to a hash with just one key/value pair
    my $paths = $self->{data}->{remote_path};
    if (ref(\$paths) eq 'SCALAR') {
        $paths = $self->{data}->{remote_path} = {'' => $paths};
    }

    # make sure each key contains only Latin characters, digits, underscore,
    # hyphen, dot, or forward slashes; then exclude directory names like '.' or '..'
    foreach (keys %$paths) {
        die "Not a valid subdirectory name: '$_'" if ($_ ne '') && ($_ !~ m/^[\w\.\-\/]+$/ || $_ =~ m/^\.+$/);
    }

    # Expand macros (environment variables) in paths
    foreach (keys %$paths) {
        $self->{data}->{remote_path}->{$_} = subst_macros($self->{data}->{remote_path}->{$_});
    }
}

sub _check_folder {
    my ($self, $data_path, $subpath, $parent_folders) = @_;
    my $local_path = $subpath eq '' ? $data_path : $data_path.'/'.$subpath;

    # if the target folder doesn't exist, quit early
    return 1 if !-e $local_path;

    print "\nChecking folder $local_path\n";

    my @a = get_directory_contents($local_path);

    # delete files and directories that shouldn't be there
    foreach my $entry (@a) {
        my $path = $subpath eq '' ? $entry : $subpath.'/'.$entry;
        my $fullpath = $local_path.'/'.$entry;
        if (-f $fullpath) {
            # allow Apple-specific file to reside in the directory
            next if $path eq '.DS_Store';

            if ($self->{initialize}) {
                print "Deleting file '$fullpath'\n";
                unlink($fullpath);
            } else {
                print "ERROR: file '$fullpath' should not be present in the local project folder\n";
                return undef; # error
            }
        } elsif (-d $fullpath
            && !exists $parent_folders->{$path}
            && !exists $self->{data}->{remote_path}->{$path}) {

            if ($self->{initialize}) {
                $self->_delete_directory($fullpath);
            } else {
                print "ERROR: directory '$fullpath' should not be present in the local project folder\n";
                return undef; # error
            }
        }
    }
    return 1; # ok
}

sub checkout_all {
    my $self = shift;

    my $paths = $self->{data}->{remote_path};

    my $data_path = $self->{data}->{local_path};

    $self->_make_directory_on_initialize($data_path);

    my $init_errors_found = undef;

    # based on the list of target paths, prepare a list of parent folders
    # to check or clean up
    my $parent_folders = {};

    foreach my $path (keys %$paths) {
        my @a = split(/\//, $path);
        pop @a; # get the parent one

        while (@a > 0) {
            $parent_folders->{join('/', @a)} = 1;
            $parent_folders->{''} = 1; # check the root as well
            pop @a;
        }
    }

    foreach my $path (sort keys %$parent_folders) {
        $init_errors_found ||= !$self->_check_folder($data_path, $path, $parent_folders);
    }

    # then go through each subfolder

    my $n = 0;
    my $total = scalar keys %$paths;
    foreach my $key (sort keys %$paths) {
        last if $init_errors_found;
        print "[", ++$n, " of $total]: /$key\n" if $total > 1;
        my $local_path = $data_path.'/'.$key;
        $self->_make_directory_on_initialize($local_path);
        my $remote_path = $paths->{$key};
        $init_errors_found ||= !$self->_update_from_vcs($local_path, $remote_path);
    }

    if ($init_errors_found) {
        print "Use --initialize option to force update the directory structure\n";
        print "\n";
        die "Must initialize data before continuing\n";
    }
}

# get remote repository URL with an optional #branch_name suffix
sub get_remote_url {
    my ($self, $local_path) = @_;
    die "Please define your get_remote_url method";
}

# return true value if plugin can switch branches without re-initializing the whole checkout
sub support_branch_switching {
    die "Please define your support_branch_switching method";
    #return 1; # example
}

# split the remothe path URL into path and branch
# (this needs to be implemented only if support_branch_switching returns true)
sub split_remote_path_branch {
    my ($self, $remote_path) = @_;

    die "Please define your split_remote_path_branch method";
    #return ($remote_path, $branch); # example
}

# split the remothe path URL into path and branch
# (this needs to be implemented only if support_branch_switching returns true)
sub switch_to_branch {
    my ($self, $local_path, $branch) = @_;
    die "Please define your switch_to_branch method";
}

# init local repository (checkout)
sub init_repo {
    my ($self, $local_path, $remote_path, $branch) = @_;
    die "Please define your init_repo method";
}

# add all unversioned files and directories in local repository
sub add_unversioned {
    my ($self, $local_path) = @_;
    die "Please define your add_unversioned method";
}

# remove all unversioned files and directories in local repository
sub delete_unversioned {
    my ($self, $local_path) = @_;
    die "Please define your delete_unversioned method";
}

# checkout (pull) changes from remote repository;
# this code should deal with fixing the state of the repository,
# abandoning local changes, resolving conflicts
sub checkout {
    my ($self, $local_path, $remote_path, $branch) = @_;
    die "Please define your checkout method";
}

# commit (push) changes to remote repository;
# this code should try to merge the remote changes and avoid conflicts
sub commit {
    my ($self, $local_path, $original_remote_path, $message) = @_;
    die "Please define your commit method";
}

sub _update_from_vcs {
    my ($self, $local_path, $expected_url) = @_;

    die "expected URL must not be blank" unless $expected_url ne '';

    my $current_url = $self->get_remote_url($local_path);

    my ($expected_branch, $current_branch);

    if ($self->support_branch_switching) {
        ($expected_url, $expected_branch) = $self->split_remote_path_branch($expected_url);
        ($current_url, $current_branch) = $self->split_remote_path_branch($current_url);
    }

    if ($expected_url ne $current_url) {
        $self->_show_url_differs_error($local_path, $expected_url, $current_url, $self->{initialize});
        return undef unless $self->{initialize};

        $self->_delete_directory($local_path);
        $self->_make_directory($local_path);

        if ($expected_url) {
            $self->init_repo($local_path, $expected_url, $expected_branch);
        }

        $current_url = $self->get_remote_url($local_path);
        if ($self->support_branch_switching) {
            ($current_url, $current_branch) = $self->split_remote_path_branch($current_url);
        }

        if ($expected_url ne $current_url) {
            die "Failed to init repository. Currently reported URL differs: '$current_url'\n";
        }

        if ($self->support_branch_switching && ($expected_branch ne $current_branch)) {
            die "Failed to init repository. Currently reported branch differs: '$current_branch'\n";
        }

        return 1; # ok
    }

    # do cleanup and checkout before switching branches to make sure
    # we can get the up-to-date list of remote branches

    $self->delete_unversioned($local_path);

    # note that here we checkout the currently reported url/branch first;
    # VCS plugins that don't support branching will not get to this point if their URL differs,
    # since they will do a full re-initialization of the local copy

    $self->checkout($local_path, $current_url, $current_branch);

    if ($self->support_branch_switching && ($expected_branch ne $current_branch)) {
        print "Switching to branch '$expected_branch'\n";
        $self->switch_to_branch($local_path, $expected_branch);
        ($current_url, $current_branch) = $self->split_remote_path_branch($self->get_remote_url($local_path));
        if ($expected_url ne $current_url) {
            die "Failed to switch to branch '$expected_branch'. Currently reported URL differs: '$current_url'\n";
        }
        if ($expected_branch ne $current_branch) {
            die "Failed to switch to branch '$expected_branch'. Currently reported branch differs: '$current_branch'\n";
        }
    }

    return 1; # ok
}

sub _show_url_differs_error {
    my ($self, $local_path, $expected_url, $current_url, $initialize) = @_;

    my $status_prefix = $initialize ? 'WARNING' : 'ERROR';

    print "\n";
    print "***************************************************************\n";
    print "$status_prefix: expected remote repository URL does not match the reported one.\n";
    print "Directory    : $local_path\n";
    print "Reported URL : $current_url\n";
    print "Expected URL : $expected_url\n";
    print "***************************************************************\n";
    print "\n";
}

sub commit_all {
    my ($self, $message) = @_;

    my $paths = $self->{data}->{remote_path};

    my $n = 0;
    my $total = scalar keys %$paths;
    foreach my $key (sort keys %$paths) {
        print "[", ++$n, " of $total]: /$key\n" if $total > 1;
        my $local_path = normalize_path($self->{data}->{local_path}.'/'.$key);
        my $remote_path = $paths->{$key};

        my $current_url = $self->get_remote_url($local_path);

        if ($remote_path ne $current_url) {
            $self->_show_url_differs_error($local_path, $remote_path, $current_url);
            die "Can't commit to an unknown repository; use 'serge pull' first to make sure the local repository checkout is properly initialized\n";
        }

        if ($self->{data}->{add_unversioned}) {
            $self->add_unversioned($local_path);
        } else {
            $self->delete_unversioned($local_path);
        }
        $self->commit($local_path, $remote_path, $message || $self->{data}->{commit_message});
    }
}

sub _make_directory_on_initialize {
    my ($self, $path) = @_;

    if (!-d $path) {
        if ($self->{initialize}) {
            $self->_make_directory($path);
        } else {
            print "\n";
            print "***************************************************************\n";
            print "ERROR: target data directory does not exist\n";
            print "Directory: $path\n";
            print "***************************************************************\n";
            print "\n";
            print "Use 'serge pull --initialize <config_file>' command to create the target data directory and do the initial checkout\n";
            print "\n";
            die "Must initialize the data before continuing\n";
        }
    }
}

sub _make_directory {
    my ($self, $path) = @_;

    return if (-d $path); # directory already exists
    die "'$path' points to a file, not a folder" if (-f $path);

    print "Creating directory '$path'\n";

    eval { mkpath($path) };
    ($@) && die "Couldn't create $path: $@";
}

sub _delete_directory {
    my ($self, $path) = @_;

    die "'$path' points to a file, not a folder" if (-f $path);

    print "Deleting directory '$path'\n";

    eval { rmtree($path) };
    ($@) && die "Couldn't delete $path: $@";
}

1;